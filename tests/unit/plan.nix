# The golden plan is compared with ==, so every field takes part and the fixture
# carries nothing the planner did not write.
{
  planner,
  support,
  folder,
  imageSource,
}:
let
  inherit (builtins)
    all
    attrNames
    concatLists
    concatStringsSep
    elemAt
    filter
    fromJSON
    genList
    isAttrs
    isList
    isString
    length
    mapAttrs
    match
    readFile
    replaceStrings
    split
    stringLength
    substring
    toJSON
    ;

  inherit (support)
    countById
    hasInfix
    messageById
    planOf
    publicString
    rowIds
    secretFile
    severityById
    soleRoot
    subjectsById
    ;

  inherit (planner.util) uniqueStrings;

  worked = support.workedResult;
  workedPlan = worked.plan;

  imageReader = import (imageSource + "/read.nix") { inherit planner; };

  fixture = fromJSON (readFile (folder + "/plan/backup.json"));

  join = path: name: if path == "" then name else "${path}.${name}";

  differencesAt =
    path: want: have:
    if isAttrs want && isAttrs have then
      concatLists (
        map (
          name:
          if have ? ${name} then
            differencesAt (join path name) want.${name} have.${name}
          else
            [ "${join path name}: in the fixture, not in the plan" ]
        ) (attrNames want)
      )
      ++ map (name: "${join path name}: in the plan, not in the fixture") (
        filter (name: !(want ? ${name})) (attrNames have)
      )
    else if isList want && isList have then
      if length want != length have then
        [
          "${path}: the fixture has ${toString (length want)} elements and the plan has ${toString (length have)}"
        ]
      else
        concatLists (
          genList (i: differencesAt "${path}[${toString i}]" (elemAt want i) (elemAt have i)) (length want)
        )
    else if want == have then
      [ ]
    else
      [ "${path}: differs" ];

  differences = differencesAt "" fixture;

  # An ellipsis, or a hash that is not sixteen hex digits, is a value somebody typed.
  # A fixture carrying one has stopped being evidence.
  shortHash =
    value:
    let
      m = match ".*sha256-([0-9a-f]*).*" value;
    in
    m != null && stringLength (elemAt m 0) != 16;

  placeholdersAt =
    path: node:
    if isAttrs node then
      concatLists (map (name: placeholdersAt (join path name) node.${name}) (attrNames node))
    else if isList node then
      concatLists (genList (i: placeholdersAt "${path}[${toString i}]" (elemAt node i)) (length node))
    else if isString node then
      (if hasInfix "..." node then [ "${path}: an ellipsis" ] else [ ])
      ++ (if shortHash node then [ "${path}: a hash that is not sixteen hex digits" ] else [ ])
    else
      [ ];

  placeholders = placeholdersAt "";

  referencedIn =
    node:
    if isAttrs node then
      concatLists (map (name: referencedIn node.${name}) (attrNames node))
    else if isList node then
      concatLists (map referencedIn node)
    else if isString node then
      let
        machine = match "(machine:[a-z][a-z0-9-]*)@sha256-[0-9a-f]+" node;
        entry = match "[a-z][a-z-]*:[a-z][a-z-]*(@[a-z][a-z0-9-]*)?" node;
      in
      if machine != null then
        [ (elemAt machine 0) ]
      else if entry != null then
        [ node ]
      else
        [ ]
    else
      [ ];

  drifted =
    key: field: value:
    fixture
    // {
      ${key} = fixture.${key} // {
        ${field} = value;
      };
    };

  collapse =
    s:
    let
      once = replaceStrings [ "  " ] [ " " ] s;
    in
    if once == s then s else collapse once;

  leadingSpaces =
    line:
    let
      go = i: if substring i 1 line == " " then go (i + 1) else i;
    in
    go 0;

  committedLines = support.lines (readFile (folder + "/plan/diagnostics.txt"));

  # Parsed off the renderer's exact layout. Change one without the other and this
  # quietly finds no rows.
  committedRowAt =
    index:
    let
      header = match "  ! ([^ ]+) +(.*)" (elemAt committedLines index);
      rest = genList (i: elemAt committedLines (index + 1 + i)) (length committedLines - index - 1);
      continuation =
        builtins.foldl'
          (
            acc: line:
            if acc.done then
              acc
            else if leadingSpaces line >= 20 then
              acc // { text = "${acc.text} ${collapse line}"; }
            else
              let
                detail = match " {6}severity: ([a-z]+).*" line;
              in
              acc
              // {
                done = true;
                severity = if detail == null then "" else elemAt detail 0;
              }
          )
          {
            text = elemAt header 1;
            severity = "";
            done = false;
          }
          rest;
    in
    if header == null then
      null
    else
      {
        subject = elemAt header 0;
        message = collapse continuation.text;
        inherit (continuation) severity;
      };

  committedRows = filter (row: row != null) (genList committedRowAt (length committedLines));

  producedRows = map (row: {
    inherit (row) subject message severity;
  }) worked.diagnostics;

  inherit (support.worked) openssh;

  # Split at the last @: a plan key carries one of its own.
  atLast =
    s:
    let
      parts = filter isString (split "@" s);
      n = length parts;
    in
    {
      key = concatStringsSep "@" (genList (i: elemAt parts i) (n - 1));
      hash = elemAt parts (n - 1);
    };

  pub = planner.interface {
    name = "pub";
    exports.publicKey = publicString;
  };

  identity = planner.interface {
    name = "identity";
    exports = {
      publicKey = publicString;
      privateKey = secretFile;
    };
  };

  quiet = _: {
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  placedOn = machines: module: {
    inherit module;
    placement.every.only = { inherit machines; };
  };

  placedWith =
    machines: knobs: module:
    (placedOn machines module) // { settings.only = knobs; };

  keysOf = result: mapAttrs (_: entry: entry.key) result.plan;
in
{
  testThePlanSerialises = {
    expr = {
      roundTrips = fromJSON (toJSON workedPlan) == workedPlan;
      entryCount = length (attrNames workedPlan);
    };
    expected = {
      roundTrips = true;
      entryCount = 11;
    };
  };

  testAServicePlacedTwice =
    let
      result = planOf {
        instances.svc = placedOn [ "one" "two" ] (soleRoot {
          module = _: {
            impl = _: {
              closure = [ openssh ];
              units.svc.command = "${openssh}/bin/sshd";
            };
          };
        });
      };
      one = result.plan."svc:only@one";
      two = result.plan."svc:only@two";
    in
    {
      expr = {
        planKeys = attrNames result.plan;
        sameUnits = one.units == two.units;
        samePlacement = one.placement == two.placement;
        sameClosure = one.closure == two.closure;
        differentHash = one.key != two.key;
        dependsOn = one.dependsOn ++ two.dependsOn;
        rows = result.diagnostics;
      };
      expected = {
        planKeys = [
          "machine:one"
          "machine:two"
          "svc:only@one"
          "svc:only@two"
        ];
        sameUnits = true;
        samePlacement = true;
        sameClosure = true;
        differentHash = true;
        dependsOn = [
          "machine:one@${result.plan."machine:one".key}"
          "machine:two@${result.plan."machine:two".key}"
        ];
        rows = [ ];
      };
    };

  testAnEntryNamesADependency =
    let
      deps = builtins.concatLists (
        planner.util.mapAttrsToList (_: entry: entry.dependsOn or [ ]) workedPlan
      );
      parsed = map atLast deps;
    in
    {
      expr = {
        dependencyCount = length deps;
        everyKeyIsInThePlan = all (d: workedPlan ? ${d.key}) parsed;
        everyHashIsThatEntrysOwn = all (d: workedPlan.${d.key}.key == d.hash) parsed;
        dependedOn = uniqueStrings (map (d: d.key) parsed);
      };
      # Four placed entries and three generated values, each naming the machine
      # whose fact reaches its key.
      expected = {
        dependencyCount = 7;
        everyKeyIsInThePlan = true;
        everyHashIsThatEntrysOwn = true;
        dependedOn = [
          "machine:alpha"
          "machine:beta"
          "machine:gamma"
          "machine:vault"
        ];
      };
    };

  testAnUnrelatedEditChangesNothing =
    let
      deployment =
        port:
        planOf {
          instances = {
            tuned = placedWith [ "one" ] { inherit port; } (soleRoot {
              module = _: {
                impl =
                  { settings, ... }:
                  {
                    closure = [ openssh ];
                    units.only.command = "${openssh}/bin/sshd -p ${toString settings.port}";
                  };
              };
              defaults.port = 22;
            });
            other = placedOn [ "two" ] (soleRoot {
              module = quiet;
            });
          };
        };
      before = deployment 22;
      after = deployment 2222;
    in
    {
      expr = {
        unrelatedKeyUnchanged = before.plan."other:only@two".key == after.plan."other:only@two".key;
        unrelatedEntryUnchanged = before.plan."other:only@two" == after.plan."other:only@two";
        editedKeyChanged = before.plan."tuned:only@one".key != after.plan."tuned:only@one".key;
        rows = before.diagnostics ++ after.diagnostics;
      };
      expected = {
        unrelatedKeyUnchanged = true;
        unrelatedEntryUnchanged = true;
        editedKeyChanged = true;
        rows = [ ];
      };
    };

  testAReadValueChangesTheReadersKey =
    let
      deployment =
        value:
        planOf {
          instances = {
            provider = {
              module = soleRoot {
                module = _: {
                  provides.thing.interface = pub;
                  impl =
                    { settings, ... }:
                    {
                      provides.thing.exports.publicKey = settings.value;
                      units.only.command = "/bin/true";
                    };
                };
                provides = [ "thing" ];
                defaults.value = "ssh-ed25519 AAAA";
              };
              placement.every.only.machines = [ "one" ];
              settings.only.value = value;
              exposes = [ "thing" ];
            };
            consumer = {
              module = soleRoot {
                module = _: {
                  uses.p = {
                    interface = pub;
                    reach = "one";
                    reads = [ "publicKey" ];
                  };
                  impl =
                    { results, ... }:
                    {
                      closure = [ openssh ];
                      units.only = {
                        command = "${openssh}/bin/sshd";
                        env.AUTHORIZED = results.p.publicKey;
                      };
                    };
                };
              };
              placement.every.only.machines = [ "two" ];
              wire.p = {
                instance = "provider";
                provides = "thing";
              };
            };
          };
        };
      before = deployment "ssh-ed25519 BEFORE";
      after = deployment "ssh-ed25519 AFTER";
    in
    {
      expr = {
        readerKeyChanged = before.plan."consumer:only@two".key != after.plan."consumer:only@two".key;
        readerEnv = [
          before.plan."consumer:only@two".env.AUTHORIZED
          after.plan."consumer:only@two".env.AUTHORIZED
        ];
        readerClosureUnchanged =
          before.plan."consumer:only@two".closure == after.plan."consumer:only@two".closure;
        readBy = after.plan."provider:only@one".provides.thing.exports.publicKey.readBy;
        rows = before.diagnostics ++ after.diagnostics;
      };
      expected = {
        readerKeyChanged = true;
        readerEnv = [
          "ssh-ed25519 BEFORE"
          "ssh-ed25519 AFTER"
        ];
        readerClosureUnchanged = true;
        readBy = [ "consumer:only@two" ];
        rows = [ ];
      };
    };

  testASetValuedReadIsInTheReadersKey =
    let
      deployment =
        betaTags:
        planOf {
          machines = {
            alpha = {
              address = "alpha.example:22";
              tags = [ "member" ];
              system = "x86_64-linux";
              serviceManager = "systemd";
            };
            beta = {
              address = "beta.example:22";
              tags = betaTags;
              system = "x86_64-linux";
              serviceManager = "systemd";
            };
            host = {
              address = "host.example:22";
              tags = [ ];
              system = "x86_64-linux";
              serviceManager = "systemd";
            };
          };
          instances = {
            provider = {
              module = soleRoot {
                module = _: {
                  provides.thing.interface = pub;
                  impl = _: {
                    provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
                    units.only.command = "/bin/true";
                  };
                };
                provides = [ "thing" ];
              };
              placement.every.only.tags = [ "member" ];
              exposes = [ "thing" ];
            };
            collector = {
              module = soleRoot {
                module = _: {
                  uses.clients = {
                    interface = pub;
                    reach = "all";
                    reads = [ "publicKey" ];
                  };
                  impl = _: {
                    units.only.command = "/bin/true";
                  };
                };
              };
              placement.every.only.machines = [ "host" ];
              wire.clients = {
                instance = "provider";
                provides = "thing";
              };
            };
          };
        };
      before = deployment [ ];
      after = deployment [ "member" ];
    in
    {
      expr = {
        membersBefore = attrNames before.plan."collector:only@host".reads.clients.entries;
        membersAfter = attrNames after.plan."collector:only@host".reads.clients.entries;
        readerKeyChanged = before.plan."collector:only@host".key != after.plan."collector:only@host".key;
        readerDependsOnUnchanged =
          before.plan."collector:only@host".dependsOn == after.plan."collector:only@host".dependsOn;
        warning = severityById "set-read-in-key" after;
        warningSubjects = subjectsById "set-read-in-key" after;
        rows = uniqueStrings (rowIds after);
        applicable = after.applicable;
      };
      expected = {
        membersBefore = [ "provider:only@alpha" ];
        membersAfter = [
          "provider:only@alpha"
          "provider:only@beta"
        ];
        readerKeyChanged = true;
        readerDependsOnUnchanged = true;
        warning = "warning";
        warningSubjects = [ "collector:only@host" ];
        rows = [ "set-read-in-key" ];
        applicable = true;
      };
    };

  testAGeneratorHasNotRun = {
    expr = {
      absentEntry = workedPlan."vault-repo:server@vault".reads.clients.entries."nightly:client@gamma";
      presentEntry = workedPlan."vault-repo:server@vault".reads.clients.entries."nightly:client@beta";
      rowIsInTheTable = countById "set-entry-absent" worked;
      rowSubjects = subjectsById "set-entry-absent" worked;
      providerRecordsTheAbsenceToo =
        workedPlan."nightly:client@gamma".provides.identity.exports.publicKey;
    };
    expected = {
      absentEntry = {
        bytes = "absent";
        publicKey = null;
        row = {
          id = "set-entry-absent";
          subject = "vault-repo:server@vault";
        };
      };
      presentEntry.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH2zYlcrdY8a7DJlJ8Az4edUdWjYfHMxcCuOpwUzwdQt root@beta";
      rowIsInTheTable = 1;
      rowSubjects = [ "vault-repo:server@vault" ];
      providerRecordsTheAbsenceToo = {
        bytes = "absent";
        plane = "env";
        readBy = [ "vault-repo:server@vault" ];
        rows = [
          {
            id = "set-entry-absent";
            subject = "vault-repo:server@vault";
          }
        ];
        secrecy = "public";
        value = null;
      };
    };
  };

  testARenderedFileOverAnIncompleteSet = {
    expr = workedPlan."vault-repo:server@vault".configData."/srv/borg/.ssh/authorized_keys";
    expected = {
      computed = false;
      mode = "0600";
      reload = [ "borgRepo" ];
      row = {
        id = "set-entry-absent";
        subject = "vault-repo:server@vault";
      };
    };
  };

  testAPrivateKeyInThePlan =
    let
      bytes = "PRIVATE-KEY-BYTES-b7f3c1d9";
      result = planOf {
        instances.holder = {
          module = soleRoot {
            module = _: {
              vars.hostKey.files = {
                "ssh_host_ed25519_key".secrecy = "secret";
                "ssh_host_ed25519_key.pub".secrecy = "public";
              };
              provides.identity.interface = identity;
              impl =
                { vars, ... }:
                {
                  closure = [ openssh ];
                  provides.identity.exports = {
                    publicKey = vars.hostKey."ssh_host_ed25519_key.pub".content;
                    privateKey = vars.hostKey."ssh_host_ed25519_key";
                  };
                  units.only = {
                    command = "${openssh}/bin/sshd";
                    env.KEYFILE = vars.hostKey."ssh_host_ed25519_key".path;
                  };
                };
            };
            provides = [ "identity" ];
          };
          placement.every.only.machines = [ "one" ];
          exposes = [ "identity" ];
        };
        varsState."holder:vars/hostKey@one" = {
          "ssh_host_ed25519_key" = {
            present = true;
            content = bytes;
          };
          "ssh_host_ed25519_key.pub" = {
            present = true;
            content = "ssh-ed25519 PUBLICHALF";
          };
        };
      };
      entry = result.plan."holder:only@one";
    in
    {
      expr = {
        privateHalf = entry.provides.identity.exports.privateKey;
        env = entry.units.only.env;
        varsRecord = entry.vars.hostKey.files."ssh_host_ed25519_key";
        bytesAnywhereInThePlan = hasInfix bytes (toJSON result.plan);
        publicBytesInThePlan = hasInfix "ssh-ed25519 PUBLICHALF" (toJSON result.plan);
        publicHalf = entry.provides.identity.exports.publicKey.value;
        rows = result.diagnostics;
      };
      expected = {
        privateHalf = {
          plane = "reference";
          readBy = [ ];
          secrecy = "secret";
          value = "/run/vars/holder/hostKey/ssh_host_ed25519_key";
        };
        env.KEYFILE = "/run/vars/holder/hostKey/ssh_host_ed25519_key";
        varsRecord = {
          deploy = true;
          inPlan = "reference";
          path = "/run/vars/holder/hostKey/ssh_host_ed25519_key";
          secrecy = "secret";
        };
        bytesAnywhereInThePlan = false;
        publicBytesInThePlan = true;
        publicHalf = "ssh-ed25519 PUBLICHALF";
        rows = [ ];
      };
    };

  testASecretWithNoReader = {
    expr = {
      privateHalf = workedPlan."nightly:client@alpha".provides.identity.exports.privateKey;
      publicHalfReadBy = workedPlan."nightly:client@alpha".provides.identity.exports.publicKey.readBy;
    };
    expected = {
      privateHalf = {
        plane = "reference";
        readBy = [ ];
        secrecy = "secret";
        value = "/run/vars/nightly/hostKey/ssh_host_ed25519_key";
      };
      publicHalfReadBy = [ "vault-repo:server@vault" ];
    };
  };

  testAFileChangesAndAUnitReloads =
    let
      deployment =
        text:
        planOf {
          instances.svc = placedWith [ "one" ] { inherit text; } (soleRoot {
            module = _: {
              impl =
                { settings, ... }:
                {
                  closure = [ openssh ];
                  configData."/etc/thing.conf" = {
                    render = [ { text = "text = ${settings.text}\n"; } ];
                    mode = "0644";
                    reload = [ "thing" ];
                  };
                  units.thing.command = "${openssh}/bin/sshd -f /etc/thing.conf";
                };
            };
            defaults.text = "before";
          });
        };
      before = (deployment "before").plan."svc:only@one";
      after = (deployment "after").plan."svc:only@one";
      file = entry: entry.configData."/etc/thing.conf";
    in
    {
      expr = {
        computed = [
          (file before).computed
          (file after).computed
        ];
        hashChanged = (file before).contentHash != (file after).contentHash;
        hashesAreHashes = all (h: hasInfix "sha256-" h) [
          (file before).contentHash
          (file after).contentHash
        ];
        reload = (file after).reload;
        closureUnchanged = before.closure == after.closure;
        keyChanged = before.key != after.key;
        unitsUnchanged = before.units == after.units;
      };
      expected = {
        computed = [
          true
          true
        ];
        hashChanged = true;
        hashesAreHashes = true;
        reload = [ "thing" ];
        closureUnchanged = true;
        keyChanged = true;
        unitsUnchanged = true;
      };
    };

  testAnEnvironmentValueChanges =
    let
      deployment =
        level:
        planOf {
          instances.svc = placedWith [ "one" ] { inherit level; } (soleRoot {
            module = _: {
              impl =
                { settings, ... }:
                {
                  closure = [ openssh ];
                  units.svc = {
                    command = "${openssh}/bin/sshd";
                    env.LOG_LEVEL = settings.level;
                  };
                };
            };
            defaults.level = "info";
          });
        };
      before = (deployment "info").plan."svc:only@one";
      after = (deployment "debug").plan."svc:only@one";
    in
    {
      expr = {
        env = [
          before.units.svc.env.LOG_LEVEL
          after.units.svc.env.LOG_LEVEL
        ];
        keyChanged = before.key != after.key;
        closureUnchanged = before.closure == after.closure;
        closure = after.closure;
      };
      expected = {
        env = [
          "info"
          "debug"
        ];
        keyChanged = true;
        closureUnchanged = true;
        closure = [ openssh ];
      };
    };

  testTwoEvaluationsOfOneInputProduceEqualKeys =
    let
      first = planner.mkPlan support.worked.args;
      second = planner.mkPlan support.worked.args;
    in
    {
      expr = {
        sameEntries = attrNames first.plan == attrNames second.plan;
        sameKeys = keysOf first == keysOf second;
        samePlan = first.plan == second.plan;
        keyCount = length (attrNames (keysOf first));
      };
      expected = {
        sameEntries = true;
        sameKeys = true;
        samePlan = true;
        keyCount = 11;
      };
    };

  testAServiceWithNoUnitsCarriesAnEntryWithNoMachine =
    let
      result = planOf {
        instances.i.module = soleRoot {
          module = _: {
            impl = _: { };
          };
        };
      };
      entry = result.plan."i:only";
    in
    {
      expr = {
        planKeys = attrNames result.plan;
        entryFields = attrNames entry;
        placement = entry.placement;
        rows = result.diagnostics;
        applicable = result.applicable;
      };
      expected = {
        planKeys = [ "i:only" ];
        entryFields = [
          "key"
          "placement"
          "settings"
        ];
        placement.reason = "every";
        rows = [ ];
        applicable = true;
      };
    };

  testAnAddressChanges =
    let
      deployment =
        address:
        planOf {
          machines = {
            one = support.machines.one // {
              inherit address;
            };
            inherit (support.machines) two;
          };
          instances = {
            provider = {
              module = soleRoot {
                module = _: {
                  claims.ports.ssh = {
                    proto = "tcp";
                    count = 1;
                    fixed = 22;
                  };
                  provides.thing.interface = pub;
                  impl = _: {
                    provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
                    units.only.command = "/bin/true";
                  };
                };
                provides = [ "thing" ];
              };
              placement.every.only.machines = [ "one" ];
              exposes = [ "thing" ];
            };
            consumer = {
              module = soleRoot {
                module = _: {
                  uses.p = {
                    interface = pub;
                    reach = "one";
                    reads = [ "publicKey" ];
                  };
                  impl =
                    { results, ... }:
                    {
                      units.only = {
                        command = "/bin/true";
                        env.AUTHORIZED = results.p.publicKey;
                      };
                    };
                };
              };
              placement.every.only.machines = [ "two" ];
              wire.p = {
                instance = "provider";
                provides = "thing";
              };
            };
          };
        };
      before = deployment "one.example:22";
      after = deployment "10.0.0.10";
      fieldOf = field: result: mapAttrs (_: entry: entry.${field} or null) result.plan;
    in
    {
      expr = {
        placedKeyChanged = before.plan."provider:only@one".key != after.plan."provider:only@one".key;
        elsewhereUnchanged = before.plan."consumer:only@two".key == after.plan."consumer:only@two".key;
        machineRecordChanged = before.plan."machine:one".key != after.plan."machine:one".key;
        otherMachineUnchanged = before.plan."machine:two".key == after.plan."machine:two".key;
        addressesRecorded = [
          before.plan."provider:only@one".target.address
          after.plan."provider:only@one".target.address
        ];
        placementsIdentical = fieldOf "placement" before == fieldOf "placement" after;
        allocationsIdentical = fieldOf "alloc" before == fieldOf "alloc" after;
        wiresIdentical = fieldOf "reads" before == fieldOf "reads" after;
        rows = before.diagnostics ++ after.diagnostics;
      };
      expected = {
        placedKeyChanged = true;
        elsewhereUnchanged = true;
        machineRecordChanged = true;
        otherMachineUnchanged = true;
        addressesRecorded = [
          "one.example:22"
          "10.0.0.10"
        ];
        placementsIdentical = true;
        allocationsIdentical = true;
        wiresIdentical = true;
        rows = [ ];
      };
    };

  testTheGoldenPlanMatches = {
    expr = {
      difference = differences workedPlan;
      entries = length (attrNames fixture);
      typedByHand = placeholders fixture;
    };
    expected = {
      difference = [ ];
      entries = 11;
      typedByHand = [ ];
    };
  };

  testAGoldenFixtureDrifts = {
    expr = differencesAt "" (drifted "vault-repo:server@vault" "key"
      "sha256-0000000000000000"
    ) workedPlan;
    expected = [ "vault-repo:server@vault.key: differs" ];
  };

  testAPlaceholderSurvivesIntoTheFixture = {
    expr = {
      elidedClosure = placeholders (
        drifted "nightly:client@alpha" "closure" [ "/nix/store/8m2c...-borgbackup-1.4.0" ]
      );
      elidedAddress = placeholders (drifted "machine:alpha" "address" "alpha.example...22");
      inventedHash = placeholders (drifted "nightly:client@alpha" "key" "sha256-a41e07d2");
    };
    expected = {
      elidedClosure = [ "nightly:client@alpha.closure[0]: an ellipsis" ];
      elidedAddress = [ "machine:alpha.address: an ellipsis" ];
      inventedHash = [ "nightly:client@alpha.key: a hash that is not sixteen hex digits" ];
    };
  };

  testTheFixtureElidesNothing = {
    expr = {
      named = filter (name: !(fixture ? ${name})) (planner.util.uniqueStrings (referencedIn fixture));
      carried = attrNames fixture;
    };
    expected = {
      named = [ ];
      carried = [
        "machine:alpha"
        "machine:beta"
        "machine:gamma"
        "machine:vault"
        "nightly:client@alpha"
        "nightly:client@beta"
        "nightly:client@gamma"
        "nightly:vars/hostKey@alpha"
        "nightly:vars/hostKey@beta"
        "nightly:vars/hostKey@gamma"
        "vault-repo:server@vault"
      ];
    };
  };

  testTheFoldersRowsAreProduced =
    let
      rendered = planner.render worked.diagnostics;
    in
    {
      expr = {
        produced = producedRows;
        committed = committedRows;
        count = length producedRows;
        everyMessageIsRendered = all (row: hasInfix row.message rendered) producedRows;
      };
      expected = {
        produced = producedRows;
        committed = producedRows;
        count = 2;
        everyMessageIsRendered = true;
      };
    };

  # The value's own entry carries the program, so a reader of the plan alone can
  # run it. Nothing else in the plan mentions it: a service entry is what a
  # machine is given, and no machine runs a generator.
  testTheProgramIsInTheEntry =
    let
      generator = "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-generate-token.drv";
      planWith =
        declared:
        planOf {
          instances.svc = {
            module = soleRoot {
              module = _: {
                vars.token = {
                  per = "instance";
                  files."key".secrecy = "secret";
                }
                // declared;
                impl =
                  { vars, ... }:
                  {
                    units.only = {
                      command = "/bin/true";
                      env.KEYFILE = vars.token."key".path;
                    };
                  };
              };
            };
            placement.every.only.machines = [ "one" ];
          };
          varsState."svc:vars/token"."key".present = true;
        };
      declaring = planWith { program = generator; };
      declaringNone = planWith { };
    in
    {
      expr = {
        rows = rowIds declaring ++ rowIds declaringNone;
        recorded = declaring.plan."svc:vars/token".program;
        # An absence rather than a path, and told apart by the key being absent.
        absent = declaringNone.plan."svc:vars/token" ? program;
        namedByTheServiceEntry = hasInfix generator (toJSON declaring.plan."svc:only@one");
        entriesNamingIt = filter (key: hasInfix generator (toJSON declaring.plan.${key})) (
          attrNames declaring.plan
        );
      };
      expected = {
        rows = [ ];
        recorded = generator;
        absent = false;
        namedByTheServiceEntry = false;
        entriesNamingIt = [ "svc:vars/token" ];
      };
    };

  # Whether bytes arrive at a path is on the file's own record, because a realiser
  # reads one entry and decides from it what it may show a unit.
  testAFileRecordCarriesItsDelivery =
    let
      result = planOf {
        instances.svc = {
          module = soleRoot {
            module = _: {
              vars = {
                root = {
                  deploy = false;
                  files."key".secrecy = "secret";
                };
                token = {
                  reads = [ "root" ];
                  files."secret".secrecy = "secret";
                };
              };
              impl =
                { vars, ... }:
                {
                  units.only = {
                    command = "/bin/true";
                    env.KEYFILE = vars.token."secret".path;
                  };
                };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
        varsState = {
          "svc:vars/root@one"."key".present = true;
          "svc:vars/token"."secret".present = true;
        };
      };
      entry = result.plan."svc:only@one";
    in
    {
      expr = {
        rows = rowIds result;
        delivered = entry.vars.token.files."secret".deploy;
        undelivered = entry.vars.root.files."key".deploy;
        # The path is recorded either way: a site that opens it is a row, which it
        # could not be if the record were absent.
        pathOfEither = [
          entry.vars.token.files."secret".path
          entry.vars.root.files."key".path
        ];
        onTheValuesOwnEntry = result.plan."svc:vars/root@one".files."key".deploy;
      };
      expected = {
        rows = [ ];
        delivered = true;
        undelivered = false;
        pathOfEither = [
          "/run/vars/svc/token/secret"
          "/run/vars/svc/root/key"
        ];
        onTheValuesOwnEntry = false;
      };
    };

  testAUnitNamesNoStorePath =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            impl = _: {
              units.say.command = "/bin/echo hello";
            };
          };
        });
      };
      entry = result.plan."svc:only@one";
      image = imageReader.read {
        inherit (result) plan;
        key = "svc:only@one";
        profile = "strict";
      };
      read = builtins.tryEval (builtins.deepSeq image image);
    in
    {
      expr = {
        recordsAClosure = entry ? closure;
        closure = entry.closure or null;
        rows = rowIds result;
        artifactRead = read.success;
        artifactClosure = if read.success then image.closure else null;
      };
      expected = {
        recordsAClosure = true;
        closure = [ ];
        rows = [ ];
        artifactRead = true;
        artifactClosure = [ ];
      };
    };

  testAPlacedServiceRunsNoUnit =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            provides.thing.interface = pub;
            impl = _: {
              provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
            };
          };
          provides = [ "thing" ];
        });
      };
      entry = result.plan."svc:only@one";
    in
    {
      expr = {
        recordsUnits = entry ? units;
        units = entry.units or null;
        rows = rowIds result;
        applicable = result.applicable;
      };
      expected = {
        recordsUnits = true;
        units = { };
        rows = [ ];
        applicable = true;
      };
    };

  testAnEntryThatIsPlacedNowhereRecordsNoUnit =
    let
      result = planOf {
        instances.svc = {
          module = soleRoot { module = quiet; };
          placement.every.only.tags = [ "nowhere" ];
        };
      };
      entry = result.plan."svc:only";
    in
    {
      expr = {
        planKeys = attrNames result.plan;
        entryFields = attrNames entry;
        placement = entry.placement.reason;
        carriesItsSettings = entry ? settings;
      };
      expected = {
        planKeys = [ "svc:only" ];
        entryFields = [
          "key"
          "placement"
          "settings"
        ];
        placement = "every";
        carriesItsSettings = true;
      };
    };

  testAUnitValueNoUnitFileHasALineFor =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            impl = _: {
              units.say = {
                command = "/bin/true";
                env.MOTD = "first\nsecond";
              };
            };
          };
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "unit-env-value-newline" result;
        subjects = subjectsById "unit-env-value-newline" result;
        namesTheUnit = hasInfix "`say`" (messageById "unit-env-value-newline" result);
        namesTheVariable = hasInfix "`MOTD`" (messageById "unit-env-value-newline" result);
        applicable = result.applicable;
        theEntryIsStillRead = attrNames result.plan."svc:only@one".units;
      };
      expected = {
        rows = [ "unit-env-value-newline" ];
        severity = "error";
        subjects = [ "svc:only@one" ];
        namesTheUnit = true;
        namesTheVariable = true;
        applicable = false;
        theEntryIsStillRead = [ "say" ];
      };
    };
}
