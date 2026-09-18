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
    any
    attrNames
    concatLists
    concatStringsSep
    elem
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
    evidenceById
    hasInfix
    messageById
    planOf
    publicString
    resolutionById
    root
    rowIds
    rowsById
    secretFile
    severityById
    soleRoot
    subjectsById
    ;

  inherit (planner.util) sortStrings uniqueStrings;

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

  # One instance whose members are all placed on one machine, which is the
  # shortest deployment with two entries claiming anything of one host.
  membersOn = machine: leaves: {
    module =
      { service, ... }:
      {
        services = mapAttrs (name: leaf: service name { module = leaf; }) leaves;
      };
    placement.every = mapAttrs (_: _: { machines = [ machine ]; }) leaves;
  };

  writesTo = path: _: {
    impl = _: {
      configData.${path} = {
        mode = "0644";
        render = [ { text = "one\n"; } ];
      };
      units.only.command = "/bin/true";
    };
  };

  # A claim in three parts, `null` standing for a field the module leaves
  # unstated, which is what the index reads as every value of it.
  claimsPort = proto: fixed: address: _: {
    claims.ports.listen = {
      inherit fixed;
    }
    // (if proto == null then { } else { inherit proto; })
    // (if address == null then { } else { inherit address; });
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  claimsFromSetting =
    { settings, ... }:
    {
      claims.ports.listen = {
        proto = "tcp";
        fixed = 5432;
        address = settings.address;
      };
      impl = _: {
        units.only.command = "/bin/true";
      };
    };

  reserving =
    machine: reserves:
    support.machines
    // {
      ${machine} = support.machines.${machine} // {
        inherit reserves;
      };
    };

  holdsAValue = _: {
    vars.hostKey.files."key".secrecy = "secret";
    impl =
      { vars, ... }:
      {
        units.only = {
          command = "/bin/true";
          env.KEYFILE = vars.hostKey."key".path;
        };
      };
  };

  runtimeDirectory = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields.runtimeDirectory = {
      type = planner.korora.string;
    };
  };

  keepsRecordsIn = units: _: {
    impl = _: {
      units = builtins.listToAttrs (
        map (unit: {
          name = unit;
          value = {
            command = "/bin/true";
            extends = [
              {
                extension = runtimeDirectory;
                values.runtimeDirectory = "records";
              }
            ];
          };
        }) units
      );
    };
  };

  groupedUnit = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields.supplementaryGroups = {
      type = planner.korora.listOf planner.korora.string;
    };
  };

  # One configuration file, whose record the caller states and whose unit the
  # caller may give an account and a group, so the readability comparison has
  # both halves to be made of.
  ownedFileAt =
    {
      path ? "/etc/thing.conf",
      owner ? null,
      group ? null,
      asUser ? null,
      groups ? [ ],
    }:
    _: {
      impl = _: {
        configData.${path} = {
          mode = "0440";
          reload = [ "only" ];
          render = [ { text = "value\n"; } ];
        }
        // (if owner == null then { } else { inherit owner; })
        // (if group == null then { } else { inherit group; });
        units.only = {
          command = "/bin/true";
        }
        // (if asUser == null then { } else { user = asUser; })
        // (
          if groups == [ ] then
            { }
          else
            {
              extends = [
                {
                  extension = groupedUnit;
                  values.supplementaryGroups = groups;
                }
              ];
            }
        );
      };
    };

  declaresDirectory = field: name: _: {
    impl = _: {
      units.only = {
        command = "/bin/true";
      }
      // {
        ${field} = [ name ];
      };
    };
  };

  # A row's own text, or the empty string where the table carries no such row, so
  # that a missing row is a comparison that failed rather than a coercion that
  # ended the evaluation of every other test.
  said =
    field: id: result:
    let
      text = field id result;
    in
    if text == null then "" else text;
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
      group = "root";
      mode = "0600";
      owner = "root";
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
          group = "root";
          mode = "0400";
          owner = "root";
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

  testTheFoldersRowsAreProduced = {
    expr = {
      committed = committedRows;
      count = length producedRows;
      table = planner.render worked.diagnostics;
    };
    expected = {
      committed = producedRows;
      count = 5;
      table = readFile (folder + "/plan/diagnostics.txt");
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
        severity = severityById "unit-value-newline" result;
        subjects = subjectsById "unit-value-newline" result;
        namesTheUnit = hasInfix "`say`" (messageById "unit-value-newline" result);
        namesTheVariable = hasInfix "`env.MOTD`" (messageById "unit-value-newline" result);
        applicable = result.applicable;
        theEntryIsStillRead = attrNames result.plan."svc:only@one".units;
      };
      expected = {
        rows = [ "unit-value-newline" ];
        severity = "error";
        subjects = [ "svc:only@one" ];
        namesTheUnit = true;
        namesTheVariable = true;
        applicable = false;
        theEntryIsStillRead = [ "say" ];
      };
    };

  testANewlineInACommandIsARow =
    let
      id = "unit-value-newline";
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            impl = _: {
              units.say.command = "/bin/true\nUser=root";
              units.quiet.command = "/bin/false";
            };
          };
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById id result;
        subjects = subjectsById id result;
        namesTheUnit = hasInfix "`say`" (said messageById id result);
        namesTheField = hasInfix "`command`" (said messageById id result);
        saysEnvironment = hasInfix "environment" (said evidenceById id result);
        applicable = result.applicable;
        theRestIsStillRead = attrNames result.plan."svc:only@one".units;
      };
      expected = {
        rows = [ id ];
        severity = "error";
        subjects = [ "svc:only@one" ];
        namesTheUnit = true;
        namesTheField = true;
        saysEnvironment = false;
        applicable = false;
        theRestIsStillRead = [
          "quiet"
          "say"
        ];
      };
    };

  testANewlineInAnExtensionValueIsTheSameRow =
    let
      id = "unit-value-newline";
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            impl = _: {
              units.say = {
                command = "/bin/true";
                extends = [
                  {
                    extension = runtimeDirectory;
                    values.runtimeDirectory = "records\nUser=root";
                  }
                ];
              };
            };
          };
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        namesTheField = hasInfix "`extends.systemd.runtimeDirectory`" (said messageById id result);
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        namesTheField = true;
        applicable = false;
      };
    };

  testANewlineInAUserNameIsReportedOnceByItsType =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            impl = _: {
              units.say = {
                command = "/bin/true";
                user = "root\nPrivateUsers=no";
              };
            };
          };
        });
      };
      unit = result.plan."svc:only@one".units.say;
    in
    {
      expr = {
        rows = rowIds result;
        namesTheField = hasInfix "`user`" (said messageById "unit-field-type-mismatch" result);
        recorded = unit ? user;
        fields = attrNames unit;
      };
      expected = {
        rows = [ "unit-field-type-mismatch" ];
        namesTheField = true;
        recorded = false;
        fields = [ "command" ];
      };
    };

  testAValueCarryingASpaceAndAQuoteIsNoRow =
    let
      value = ''one "two" three\four'';
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            impl = _: {
              units.say = {
                command = "/bin/true ${value}";
                env.MOTD = value;
              };
            };
          };
        });
      };
      unit = result.plan."svc:only@one".units.say;
    in
    {
      expr = {
        rows = rowIds result;
        applicable = result.applicable;
        command = unit.command;
        motd = unit.env.MOTD;
      };
      expected = {
        rows = [ ];
        applicable = true;
        command = "/bin/true ${value}";
        motd = value;
      };
    };

  testANewlineInAConfigurationFilePathIsARow =
    let
      id = "config-file-path-refused";
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = writesTo "/etc/one\n/etc/two";
        });
      };
      entry = result.plan."svc:only@one";
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById id result;
        subjects = subjectsById id result;
        namesThePath = hasInfix "/etc/one" (said messageById id result);
        namesWhatIsAdmitted = hasInfix "`~`" (said messageById id result);
        configData = entry.configData or { };
      };
      expected = {
        rows = [ id ];
        severity = "error";
        subjects = [ "svc:only@one" ];
        namesThePath = true;
        namesWhatIsAdmitted = true;
        configData = { };
      };
    };

  testAConfigurationFilePathCarryingAShellMetacharacterIsARow =
    let
      id = "config-file-path-refused";
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = writesTo "/etc/x$(id -u).conf";
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        applicable = result.applicable;
        namesThePath = hasInfix "/etc/x$(id -u).conf" (said messageById id result);
      };
      expected = {
        rows = [ id ];
        applicable = false;
        namesThePath = true;
      };
    };

  testAConfigurationFilePathCarryingAQuoteIsARow =
    let
      id = "config-file-path-refused";
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = writesTo "/etc/a\"b.conf";
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById id result;
        theSubjectIsAPlanKey = subjectsById id result == [ "svc:only@one" ];
        namesThePath = hasInfix "/etc/a\"b.conf" (said messageById id result);
      };
      expected = {
        rows = [ id ];
        subjects = [ "svc:only@one" ];
        theSubjectIsAPlanKey = true;
        namesThePath = true;
      };
    };

  testARefusedPathIsLeftOutOfTheEntryRecord =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            impl = _: {
              configData."/etc/kept.conf" = {
                mode = "0644";
                render = [ { text = "one\n"; } ];
              };
              configData."/etc/x;rm -rf /.conf" = {
                mode = "0644";
                render = [ { text = "two\n"; } ];
              };
              units.only.command = "${openssh}/bin/ssh";
              closure = [ openssh ];
            };
          };
        });
      };
      entry = result.plan."svc:only@one";
      mentions =
        node:
        if isAttrs node then
          any (name: hasInfix "rm -rf" name || mentions node.${name}) (attrNames node)
        else if isList node then
          any mentions node
        else if isString node then
          hasInfix "rm -rf" node
        else
          false;
    in
    {
      expr = {
        rows = rowIds result;
        configData = attrNames entry.configData;
        units = attrNames entry.units;
        closure = entry.closure;
        anywhereInThePlan = mentions result.plan;
      };
      expected = {
        rows = [ "config-file-path-refused" ];
        configData = [ "/etc/kept.conf" ];
        units = [ "only" ];
        closure = [ openssh ];
        anywhereInThePlan = false;
      };
    };

  testAClaimedInterfaceRecordsItsClaim =
    let
      claimed = planner.interface {
        name = "pub";
        exports.publicKey = publicString;
        id = "example.com/pub";
      };
      result = planOf {
        interfaces."interfaces/default.nix".pub = claimed;
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            provides.thing.interface = claimed;
            impl = _: {
              provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
              units.only.command = "/bin/true";
            };
          };
          provides = [ "thing" ];
        });
      };
      record = result.plan."svc:only@one".provides.thing;
    in
    {
      expr = {
        inherit (record) interface declaringFile interfaceId;
        recorded = attrNames record;
      };
      expected = {
        interface = "pub";
        declaringFile = "interfaces/default.nix";
        interfaceId = "example.com/pub";
        recorded = [
          "declaringFile"
          "exports"
          "interface"
          "interfaceId"
          "keysetEqualsInterface"
        ];
      };
    };

  testAnUnclaimedInterfaceRecordsNoClaim =
    let
      publishing = _: {
        provides.thing.interface = pub;
        impl = _: {
          provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
          units.only.command = "/bin/true";
        };
      };
      result = planOf {
        interfaces."interfaces/default.nix".pub = pub;
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = publishing;
          provides = [ "thing" ];
        });
      };
      record = result.plan."svc:only@one".provides.thing;
    in
    {
      expr = {
        recorded = attrNames record;
        claimed = record ? interfaceId;
        fixtureCarriesNone = filter (line: hasInfix "interfaceId" line) (
          support.lines (readFile (folder + "/plan/backup.json"))
        );
      };
      expected = {
        recorded = [
          "declaringFile"
          "exports"
          "interface"
          "keysetEqualsInterface"
        ];
        claimed = false;
        fixtureCarriesNone = [ ];
      };
    };

  testAClaimDoesNotReKeyAnEntry =
    let
      claimed = planner.interface {
        name = "pub";
        exports.publicKey = publicString;
        id = "example.com/pub";
      };
      run =
        iface:
        planOf {
          interfaces."interfaces/default.nix".pub = iface;
          instances.svc = placedOn [ "one" ] (soleRoot {
            module = _: {
              provides.thing.interface = iface;
              impl = _: {
                provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
                units.only.command = "/bin/true";
              };
            };
            provides = [ "thing" ];
          });
        };
      before = run pub;
      after = run claimed;
    in
    {
      expr = {
        keys = keysOf after == keysOf before;
        entryKeys = attrNames after.plan == attrNames before.plan;
        theClaimLanded = after.plan."svc:only@one".provides.thing.interfaceId;
      };
      expected = {
        keys = true;
        entryKeys = true;
        theClaimLanded = "example.com/pub";
      };
    };

  # A machine carrying the separator produced a delivery set naming `ta`, a
  # machine nothing declared, because the set is derived by splitting the key.
  testAMachineNameCarriesTheKeySeparator =
    let
      result = planOf {
        machines = {
          one = {
            address = "one.example:22";
            tags = [ "everywhere" ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
          "be@ta" = {
            address = "beta.example:22";
            tags = [ "everywhere" ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
        };
        instances = {
          issuer =
            (placedOn [ "one" ] (soleRoot {
              module = _: {
                vars.session = {
                  per = "instance";
                  files."token".secrecy = "secret";
                };
                provides.thing.interface = identity;
                impl =
                  { vars, ... }:
                  {
                    provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
                    provides.thing.exports.privateKey = vars.session."token";
                    units.only.command = "/bin/true";
                  };
              };
              provides = [ "thing" ];
            }))
            // {
              exposes = [ "thing" ];
            };
          consumer =
            (placedOn [ "be@ta" ] (soleRoot {
              module = _: {
                uses.slot = {
                  interface = identity;
                  reads = [ "privateKey" ];
                };
                impl =
                  { results, ... }:
                  {
                    units.only = {
                      command = "/bin/true";
                      env.KEYFILE = results.slot.privateKey.path;
                    };
                  };
              };
            }))
            // {
              wire.slot = {
                instance = "issuer";
                provides = "thing";
              };
            };
        };
        varsState."issuer:vars/session"."token".present = true;
      };
      value = result.plan."issuer:vars/session";
    in
    {
      expr = {
        namesTheMachine = subjectsById "name-carries-key-separator" result;
        message = messageById "name-carries-key-separator" result;
        keysNamingIt = filter (k: hasInfix "be@ta" k || hasInfix "@ta" k) (attrNames result.plan);
        delivery = value.delivery;
      };
      expected = {
        namesTheMachine = [ "deployment/machines.nix" ];
        message = "a machine of the registry is named `be@ta`, and a name a plan key is built from is a non-empty name of no control character and none of `/`, `@`, `:`";
        keysNamingIt = [ ];
        delivery = [ "one" ];
      };
    };

  # Every name a key is built from, in the reading that owns it: an instance and
  # a member in the resolver, a generator in the module reading.
  testAnInstanceOrMemberNameCarriesTheKeySeparator =
    let
      result = planOf {
        instances = {
          "a:b" = placedOn [ "one" ] (soleRoot {
            module = quiet;
          });
          ok = {
            module = root {
              members."x@y" = {
                module = quiet;
              };
            };
            placement.every."x@y".machines = [ "one" ];
          };
          gen = placedOn [ "one" ] (soleRoot {
            module = _: {
              vars."g/h".per = "instance";
              impl = _: { units.only.command = "/bin/true"; };
            };
          });
        };
      };
      messages = map (r: r.message) (rowsById "name-carries-key-separator" result);
    in
    {
      expr = {
        rows = countById "name-carries-key-separator" result;
        named = map (m: hasInfix "`a:b`" m || hasInfix "`x@y`" m || hasInfix "`g/h`" m) messages;
        keysNamingThem = filter (k: hasInfix "a:b" k || hasInfix "x@y" k || hasInfix "g/h" k) (
          attrNames result.plan
        );
        # The refused name earns the row that explains it and no second row
        # stating its root does not own it: the root does, and the reading is
        # what left it out.
        every = sortStrings (rowIds result);
      };
      expected = {
        rows = 3;
        named = [
          true
          true
          true
        ];
        keysNamingThem = [ ];
        every = [
          "name-carries-key-separator"
          "name-carries-key-separator"
          "name-carries-key-separator"
        ];
      };
    };

  # The guard is the three characters the key's structure spends, and no more:
  # hyphens, digits and underscores are inside the grammar, and the `vars/` a
  # value key carries is the planner's own text rather than a declared name.
  testAWellFormedNameIsUnaffected =
    let
      declaredMachines = attrNames support.worked.args.machines;
      declaredInstances = attrNames support.worked.args.instances;
      firstColon =
        key:
        let
          m = match "([^:@]+):.*" key;
        in
        if m == null then null else elemAt m 0;
      lastAt =
        key:
        let
          m = match ".*@([^@]+)" key;
        in
        if m == null then null else elemAt m 0;
      entryKeys = filter (k: firstColon k != "machine") (attrNames workedPlan);
    in
    {
      expr = {
        rows = countById "name-carries-key-separator" worked;
        everyInstanceIsDeclared = all (k: elem (firstColon k) declaredInstances) entryKeys;
        everyMachineIsDeclared = all (m: elem m declaredMachines) (
          filter (m: m != null) (map lastAt entryKeys)
        );
        theValueNamespaceIsStillSpelled = filter (k: hasInfix ":vars/" k) entryKeys != [ ];
      };
      expected = {
        rows = 0;
        everyInstanceIsDeclared = true;
        everyMachineIsDeclared = true;
        theValueNamespaceIsStillSpelled = true;
      };
    };

  # The three additions to the grammar, at the four declarations a key is built
  # from: the empty name at a machine and at a generator, a line break at an
  # instance and a tab at a member. Each earns the row a separator already
  # earns, and the instance that named nothing wrong is planned beside them.
  testAnEmptyNameIsRefusedByTheKeyGrammar =
    let
      id = "name-carries-key-separator";
      result = planOf {
        machines = support.machines // {
          "" = {
            address = "nowhere.example:22";
            tags = [ "everywhere" ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
        };
        instances = {
          ${"in\nstance"} = placedOn [ "one" ] (soleRoot {
            module = quiet;
          });
          ok = {
            module = root {
              members.${"mem\tber"} = {
                module = quiet;
              };
            };
            placement.every.${"mem\tber"}.machines = [ "one" ];
          };
          gen = placedOn [ "one" ] (soleRoot {
            module = _: {
              vars."".per = "instance";
              impl = _: { units.only.command = "/bin/true"; };
            };
          });
          fine = placedOn [ "one" ] (soleRoot {
            module = quiet;
          });
        };
      };
      messages = map (r: r.message) (rowsById id result);
    in
    {
      expr = {
        every = sortStrings (rowIds result);
        # Each row names the declaration it is about and the name it refused,
        # the line break reaching the sentence as the space `oneLine` made of it.
        named = map (needle: any (m: hasInfix needle m) messages) [
          "a machine of the registry is named ``"
          "an instance of the deployment is named `in stance`"
          "a member of the root of instance `ok` is named `mem\tber`"
          "generator `` of "
        ];
        # The refused name earns the row and the rest of the deployment is read
        # around it: the well-formed instance, the instance whose generator was
        # the name at fault, and the machine record every placement depends on.
        notPlanned = filter (key: !(result.plan ? ${key})) [
          "fine:only@one"
          "gen:only@one"
          "machine:one"
        ];
        theGoodEntryStillRunsItsUnit = attrNames result.plan."fine:only@one".units;
      };
      expected = {
        every = [
          "name-carries-key-separator"
          "name-carries-key-separator"
          "name-carries-key-separator"
          "name-carries-key-separator"
        ];
        named = [
          true
          true
          true
          true
        ];
        notPlanned = [ ];
        theGoodEntryStillRunsItsUnit = [ "only" ];
      };
    };

  # `machine` is a legal instance name and `one` a legal member name, so the
  # keyspace holds a machine's own record and an unplaced service entry under
  # `machine:one`. The row is the one neither family's own reading can make, so
  # it names both claimants rather than the family it was noticed from.
  testTwoClaimantsOfOnePlanKeyAreBothNamed =
    let
      id = "plan-key-claimed-twice";
      result = planOf {
        instances = {
          machine = {
            module = root {
              members.one = {
                module = quiet;
              };
            };
          };
          svc = placedOn [ "one" ] (soleRoot {
            module = quiet;
          });
        };
      };
    in
    {
      expr = {
        # One collision, one row, however many of the two readings observed it.
        count = countById id result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`machine:one`"
          "the record of machine `one`"
          "the unplaced entry of member `one` of instance `machine`"
        ];
        applicable = result.applicable;
      };
      expected = {
        count = 1;
        severity = "error";
        subjects = [ "machine:one" ];
        names = [
          true
          true
          true
        ];
        applicable = false;
      };
    };

  testAMemberIsDeclaredUnderAKeyOtherThanItsOwnName =
    let
      result = planOf {
        instances.svc = {
          module =
            { service, ... }:
            {
              services.pg = service "postgres" { module = quiet; };
            };
          placement.every.pg.machines = [ "one" ];
        };
      };
      row = builtins.head (rowsById "member-name-disagrees" result);
    in
    {
      expr = {
        rows = rowIds result;
        namesBoth = [
          (hasInfix "`pg`" row.message)
          (hasInfix "`postgres`" row.message)
        ];
        keys = attrNames result.plan;
        readTheWholePlan = (builtins.tryEval (builtins.deepSeq result.plan true)).success;
      };
      expected = {
        rows = [ "member-name-disagrees" ];
        namesBoth = [
          true
          true
        ];
        keys = [
          "machine:one"
          "svc:pg@one"
        ];
        readTheWholePlan = true;
      };
    };

  testAGeneratorDeclaresNoFiles =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            vars.token.per = "instance";
            impl = _: { units.only.command = "/bin/true"; };
          };
        });
      };
      value = result.plan."svc:vars/token";
    in
    {
      expr = {
        rows = rowIds result;
        recorded = value ? files;
        files = value.files;
      };
      expected = {
        rows = [ ];
        recorded = true;
        files = { };
      };
    };

  testAnEntryRecordsAnEmptyCollectionAReaderDependsOn =
    let
      # An entry that publishes an export and runs nothing: both collections a
      # realisation reads are empty, so moving either back into `pruned` is
      # observable here rather than only in the half that happens to be empty.
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
        rows = rowIds result;
        recorded = [
          (entry ? closure)
          (entry ? units)
        ];
        closure = entry.closure;
        units = entry.units;
      };
      expected = {
        rows = [ ];
        recorded = [
          true
          true
        ];
        closure = [ ];
        units = { };
      };
    };

  # No field says when a file's bytes exist: the disposition and the presence of a
  # `ref` already do, and these two tests are what a realiser reads to decide
  # whether it can carry the path.
  testAFileWhoseBytesExistAtBuildTime =
    let
      result = planOf {
        instances.svc = placedWith [ "one" ] { } (soleRoot {
          module = _: {
            impl = _: {
              closure = [ openssh ];
              configData = {
                "/etc/from-store.conf" = {
                  source = "${openssh}/etc/ssh/ssh_config";
                  mode = "0444";
                  reload = [ "thing" ];
                };
                "/etc/from-literals.conf" = {
                  render = [
                    { text = "one\n"; }
                    { text = "two\n"; }
                  ];
                  mode = "0444";
                  reload = [ "thing" ];
                };
              };
              units.thing.command = "${openssh}/bin/sshd";
            };
          };
        });
      };
      files = result.plan."svc:only@one".configData;
      fromStore = files."/etc/from-store.conf";
      fromLiterals = files."/etc/from-literals.conf";
    in
    {
      expr = {
        rows = rowIds result;
        storeKeys = attrNames fromStore;
        literalKeys = attrNames fromLiterals;
        source = fromStore.source;
        # Every item is a literal, so the plan holds every byte it hashed.
        literals = map (i: i.text) fromLiterals.render;
        hashedContent = hasInfix "sha256-" fromLiterals.contentHash;
      };
      expected = {
        rows = [ ];
        storeKeys = [
          "computed"
          "group"
          "mode"
          "owner"
          "reload"
          "source"
        ];
        literalKeys = [
          "computed"
          "contentHash"
          "group"
          "mode"
          "owner"
          "reload"
          "render"
        ];
        source = "${openssh}/etc/ssh/ssh_config";
        literals = [
          "one\n"
          "two\n"
        ];
        hashedContent = true;
      };
    };

  testAFileWhoseBytesExistOnlyOnTheMachine =
    let
      result = planOf {
        instances.holder = {
          module = soleRoot {
            module = _: {
              vars.hostKey.files."key".secrecy = "secret";
              impl =
                { vars, ... }:
                {
                  closure = [ openssh ];
                  configData."/etc/agent.conf" = {
                    mode = "0400";
                    reload = [ "thing" ];
                    render = [
                      { text = "key_file = "; }
                      { ref = vars.hostKey."key".path; }
                    ];
                  };
                  units.thing.command = "${openssh}/bin/sshd";
                };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
        varsState."holder:vars/hostKey@one"."key" = {
          present = true;
          content = "PRIVATE-KEY-BYTES";
        };
      };
      file = result.plan."holder:only@one".configData."/etc/agent.conf";
    in
    {
      expr = {
        rows = rowIds result;
        keys = attrNames file;
        # The reference path is named, and nothing digests the assembled bytes.
        references = map (i: i.ref or null) file.render;
        hashedStructure = hasInfix "sha256-" file.structureHash;
        hashedContent = file ? contentHash;
      };
      expected = {
        rows = [ ];
        keys = [
          "computed"
          "group"
          "mode"
          "owner"
          "reload"
          "render"
          "structureHash"
        ];
        references = [
          null
          "/run/vars/holder/hostKey/key"
        ];
        hashedStructure = true;
        hashedContent = false;
      };
    };

  # An entry key carries its own instance name, so the second instance of the
  # scenario is a second deployment under the same name: two instances of one
  # module cannot carry equal keys by construction.
  testTheEntriesOfAKeptMemberAreUnchangedByACut =
    let
      pair =
        { service, ... }:
        {
          services = {
            keeper = service "keeper" { module = quiet; };
            spare = service "spare" { module = quiet; };
          };
        };
      whole = planOf {
        instances.svc = {
          module = pair;
          placement.every = {
            keeper.machines = [ "one" ];
            spare.machines = [ "two" ];
          };
        };
      };
      cut = planOf {
        instances.svc = {
          module = pair;
          members.spare.enable = false;
          placement.every.keeper.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        rows = rowIds whole ++ rowIds cut;
        keptKeyUnchanged = whole.plan."svc:keeper@one".key == cut.plan."svc:keeper@one".key;
        keptEntryDifference =
          differencesAt "svc:keeper@one" whole.plan."svc:keeper@one"
            cut.plan."svc:keeper@one";
        wholeKeys = attrNames whole.plan;
        cutKeys = attrNames cut.plan;
        namingTheCutMember = filter (key: hasInfix "spare" (toJSON cut.plan.${key})) (attrNames cut.plan);
      };
      expected = {
        rows = [ ];
        keptKeyUnchanged = true;
        keptEntryDifference = [ ];
        wholeKeys = [
          "machine:one"
          "machine:two"
          "svc:keeper@one"
          "svc:spare@two"
        ];
        cutKeys = [
          "machine:one"
          "svc:keeper@one"
        ];
        namingTheCutMember = [ ];
      };
    };

  testACutMembersGeneratedValueIsNotRecorded =
    let
      pair =
        { service, ... }:
        {
          services = {
            keeper = service "keeper" { module = quiet; };
            spare = service "spare" {
              module = _: {
                vars.token = {
                  per = "instance";
                  files."key".secrecy = "secret";
                };
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
          };
        };
      # The same state either way, so the absence is the cut's and not a missing
      # answer about whether the value exists.
      state.varsState."svc:vars/token"."key".present = true;
      whole = planOf (
        {
          instances.svc = {
            module = pair;
            placement.every = {
              keeper.machines = [ "one" ];
              spare.machines = [ "two" ];
            };
          };
        }
        // state
      );
      cut = planOf (
        {
          instances.svc = {
            module = pair;
            members.spare.enable = false;
            placement.every.keeper.machines = [ "one" ];
          };
        }
        // state
      );
    in
    {
      expr = {
        rows = rowIds whole ++ rowIds cut;
        keptRecordsTheValue = whole.plan ? "svc:vars/token";
        cutRecordsTheValue = cut.plan ? "svc:vars/token";
        cutKeys = attrNames cut.plan;
        dependsOn = concatLists (planner.util.mapAttrsToList (_: entry: entry.dependsOn or [ ]) cut.plan);
        namingTheGenerator = filter (key: hasInfix "vars/token" (toJSON cut.plan.${key})) (
          attrNames cut.plan
        );
      };
      expected = {
        rows = [ ];
        keptRecordsTheValue = true;
        cutRecordsTheValue = false;
        cutKeys = [
          "machine:one"
          "svc:keeper@one"
        ];
        dependsOn = [ "machine:one@${cut.plan."machine:one".key}" ];
        namingTheGenerator = [ ];
      };
    };

  # `keeper` is one module value shared by the two roots: the surviving member's
  # declaration has to be identical, so the only difference is whether the root
  # declares the second member at all.
  testThePlanDoesNotSayWhatWasCut =
    let
      keeper = quiet;
      pair =
        { service, ... }:
        {
          services = {
            keeper = service "keeper" { module = keeper; };
            spare = service "spare" { module = quiet; };
          };
        };
      solo =
        { service, ... }:
        {
          services.keeper = service "keeper" { module = keeper; };
        };
      cut = planOf {
        instances.svc = {
          module = pair;
          members.spare.enable = false;
          placement.every.keeper.machines = [ "one" ];
        };
      };
      never = planOf {
        instances.svc = {
          module = solo;
          placement.every.keeper.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        rows = rowIds cut ++ rowIds never;
        equal = cut.plan == never.plan;
        difference = differencesAt "" cut.plan never.plan;
      };
      expected = {
        rows = [ ];
        equal = true;
        difference = [ ];
      };
    };

  # Both providers export the same value, so a field that moved moved because the
  # read moved and not because the bytes did.
  testAConsumerWhoseReadMovedToAWiredProvider =
    let
      provider = _: {
        provides.api.interface = pub;
        impl = _: {
          provides.api.exports.publicKey = "ssh-ed25519 AAAA";
          units.only.command = "/bin/true";
        };
      };
      consumer = _: {
        uses.api = {
          interface = pub;
          reach = "one";
          reads = [ "publicKey" ];
        };
        impl =
          { results, ... }:
          {
            units.only = {
              command = "/bin/true";
              env.AUTHORIZED = results.api.publicKey;
            };
          };
      };
      trio =
        { service, ... }:
        let
          backend = service "backend" { module = provider; };
        in
        {
          services = {
            inherit backend;
            sidecar = service "sidecar" { module = quiet; };
            app = service "app" {
              module = consumer;
              wire.api = backend.provides.api;
            };
          };
        };
      far = {
        module = soleRoot {
          module = provider;
          provides = [ "api" ];
        };
        placement.every.only.machines = [ "two" ];
        exposes = [ "api" ];
      };
      whole = planOf {
        instances = {
          inherit far;
          svc = {
            module = trio;
            placement.every = {
              backend.machines = [ "two" ];
              sidecar.machines = [ "one" ];
              app.machines = [ "one" ];
            };
          };
        };
      };
      cut = planOf {
        instances = {
          inherit far;
          svc = {
            module = trio;
            members.backend.enable = false;
            placement.every = {
              sidecar.machines = [ "one" ];
              app.machines = [ "one" ];
            };
            wire.app.api = {
              instance = "far";
              provides = "api";
            };
          };
        };
      };
      bound = whole.plan."svc:app@one";
      wired = cut.plan."svc:app@one";
    in
    {
      expr = {
        rows = rowIds whole ++ rowIds cut;
        sameFields = attrNames bound == attrNames wired;
        moved = filter (name: bound.${name} != wired.${name}) (attrNames bound);
        readBound = bound.reads.api.entry;
        readWired = wired.reads.api.entry;
        siblingDifference =
          differencesAt "svc:sidecar@one" whole.plan."svc:sidecar@one"
            cut.plan."svc:sidecar@one";
        wholeKeys = attrNames whole.plan;
        cutKeys = attrNames cut.plan;
      };
      expected = {
        rows = [ ];
        sameFields = true;
        moved = [
          "key"
          "reads"
        ];
        readBound = "svc:backend@two";
        readWired = "far:only@two";
        siblingDifference = [ ];
        wholeKeys = [
          "far:only@two"
          "machine:one"
          "machine:two"
          "svc:app@one"
          "svc:backend@two"
          "svc:sidecar@one"
        ];
        cutKeys = [
          "far:only@two"
          "machine:one"
          "machine:two"
          "svc:app@one"
          "svc:sidecar@one"
        ];
      };
    };

  testTwoEntriesOnOneMachineWriteOneHostPath =
    let
      result = planOf {
        instances.svc = membersOn "one" {
          first = writesTo "/etc/x.conf";
          second = writesTo "/etc/x.conf";
        };
      };
      id = "entry-host-path-claimed-twice";
    in
    {
      expr = {
        rows = rowIds result;
        count = countById id result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`svc:first@one`"
          "`svc:second@one`"
          "`one`"
          "`/etc/x.conf`"
        ];
        resolutionNamesTheEntrysIdentity = hasInfix "`instance` and `member`" (resolutionById id result);
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        count = 1;
        severity = "error";
        subjects = [ "svc:first@one" ];
        names = [
          true
          true
          true
          true
        ];
        resolutionNamesTheEntrysIdentity = true;
        applicable = false;
      };
    };

  # Nesting is equality observed one directory up, and a longer name beginning
  # with another's text is neither: `/etc/apple` is not inside `/etc/app`, so
  # both paths exist at once and the entry is shown both.
  testAShownHostPathSharingAPrefixWithAnotherIsNotNested =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = _: {
            impl = _: {
              configData = {
                "/etc/app" = {
                  mode = "0644";
                  render = [ { text = "one\n"; } ];
                };
                "/etc/apple" = {
                  mode = "0644";
                  render = [ { text = "two\n"; } ];
                };
              };
              units.only.command = "/bin/true";
            };
          };
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        shown = sortStrings (attrNames result.plan."svc:only@one".configData);
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        shown = [
          "/etc/app"
          "/etc/apple"
        ];
        applicable = true;
      };
    };

  # The protocol is part of the claim, so the second deployment below claims one
  # number twice and collides with nobody. Both claims state an address, so the
  # row names the one the contention is on.
  testTwoEntriesOnOneMachineClaimOnePort =
    let
      id = "entry-port-claimed-twice";
      shared = planOf {
        instances.svc = membersOn "one" {
          first = claimsPort "tcp" 5432 "10.0.0.11";
          second = claimsPort "tcp" 5432 "10.0.0.11";
        };
      };
      crossProtocol = planOf {
        instances.svc = membersOn "one" {
          first = claimsPort "tcp" 5432 "10.0.0.11";
          second = claimsPort "udp" 5432 "10.0.0.11";
        };
      };
    in
    {
      expr = {
        rows = rowIds shared;
        severity = severityById id shared;
        subjects = subjectsById id shared;
        names = map (needle: hasInfix needle (said messageById id shared)) [
          "`svc:first@one`"
          "`svc:second@one`"
          "`one`"
          "`5432`"
          "protocol `tcp`"
          "address `10.0.0.11`"
        ];
        acrossProtocols = rowIds crossProtocol;
        applicable = [
          shared.applicable
          crossProtocol.applicable
        ];
      };
      expected = {
        rows = [ id ];
        severity = "error";
        subjects = [ "svc:first@one" ];
        names = [
          true
          true
          true
          true
          true
          true
        ];
        acrossProtocols = [ ];
        applicable = [
          false
          true
        ];
      };
    };

  testTwoEntriesOnOneMachineShareOneUnitDirectory =
    let
      id = "entry-unit-directory-shared";
      result = planOf {
        instances.svc = membersOn "one" {
          first = keepsRecordsIn [ "only" ];
          second = keepsRecordsIn [ "only" ];
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`svc:first@one`"
          "`svc:second@one`"
          "`one`"
          "`runtimeDirectory/records`"
        ];
        evidenceNamesTheRestart = hasInfix "deletes a runtime directory" (said evidenceById id result);
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        severity = "warning";
        subjects = [ "svc:first@one" ];
        names = [
          true
          true
          true
          true
        ];
        evidenceNamesTheRestart = true;
        applicable = true;
      };
    };

  testOneMemberPlacedOnTwoMachinesClaimsItsPathOnEach =
    let
      result = planOf {
        instances.svc = placedOn [ "one" "two" ] (soleRoot {
          module = writesTo "/etc/x.conf";
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        recorded = map (key: attrNames result.plan.${key}.configData) [
          "svc:only@one"
          "svc:only@two"
        ];
      };
      expected = {
        rows = [ ];
        recorded = [
          [ "/etc/x.conf" ]
          [ "/etc/x.conf" ]
        ];
      };
    };

  testTwoUnitsOfOneEntryShareItsDirectory =
    let
      result = planOf {
        instances.svc = membersOn "one" {
          only = keepsRecordsIn [
            "first"
            "second"
          ];
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        units = attrNames result.plan."svc:only@one".units;
      };
      expected = {
        rows = [ ];
        units = [
          "first"
          "second"
        ];
      };
    };

  testACollisionIsReportedOnceAndNamesBothEntries =
    let
      id = "entry-port-claimed-twice";
      result = planOf {
        instances.svc = membersOn "one" {
          alpha = claimsPort "tcp" 5432 "10.0.0.11";
          beta = claimsPort "tcp" 5432 "10.0.0.11";
          gamma = claimsPort "tcp" 5432 "10.0.0.11";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        count = countById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`svc:alpha@one`"
          "`svc:beta@one`"
          "`svc:gamma@one`"
          "address `10.0.0.11`"
        ];
      };
      expected = {
        rows = [ id ];
        count = 1;
        subjects = [ "svc:alpha@one" ];
        names = [
          true
          true
          true
          true
        ];
      };
    };

  testAConfigurationFileStatingAnOwnerAndAGroup =
    let
      owned = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = ownedFileAt {
            owner = "postgres";
            group = "postgres";
          };
        });
      };
      plain = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = ownedFileAt { };
        });
      };
    in
    {
      expr = {
        rows = rowIds owned;
        record = owned.plan."svc:only@one".configData."/etc/thing.conf";
        keyMoved = owned.plan."svc:only@one".key != plain.plan."svc:only@one".key;
      };
      expected = {
        rows = [ ];
        record = {
          computed = true;
          contentHash = "sha256-1e1f2c881ae0608e";
          group = "postgres";
          mode = "0440";
          owner = "postgres";
          reload = [ "only" ];
          render = [ { text = "value\n"; } ];
        };
        keyMoved = true;
      };
    };

  testAConfigurationFileStatingNoOwnership =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = ownedFileAt { };
        });
      };
      record = result.plan."svc:only@one".configData."/etc/thing.conf";
    in
    {
      expr = {
        rows = rowIds result;
        owner = record.owner;
        group = record.group;
        statedAsFields = [
          (record ? owner)
          (record ? group)
        ];
      };
      expected = {
        rows = [ ];
        owner = "root";
        group = "root";
        statedAsFields = [
          true
          true
        ];
      };
    };

  # The projection removes the ownership keys the declaration did not state, so a
  # deployment that states none keys exactly as it did before the record could
  # carry one. The fixture is the evidence for the whole worked plan; these two
  # entries are the evidence that stating one moves one key and no other.
  testOnlyTheOwnershipStatedEntersTheKey =
    let
      twoFiles =
        ownership:
        planOf {
          instances.svc = membersOn "one" {
            first = ownedFileAt (ownership // { path = "/etc/first.conf"; });
            second = ownedFileAt { path = "/etc/second.conf"; };
          };
        };
      plain = twoFiles { };
      grouped = twoFiles { group = "borg"; };
    in
    {
      expr = {
        rows = rowIds grouped;
        fixtureKeyHeld = workedPlan."vault-repo:server@vault".key;
        moved = plain.plan."svc:first@one".key != grouped.plan."svc:first@one".key;
        theOtherHeld = plain.plan."svc:second@one".key == grouped.plan."svc:second@one".key;
      };
      expected = {
        rows = [ ];
        fixtureKeyHeld = "sha256-a090a60d56683eba";
        moved = true;
        theOtherHeld = true;
      };
    };

  # The other half of the two statements that state nothing: a value differing
  # from the one the field resolves to unstated asks for a different file, so it
  # moves that record's key and no other. The generated file's mode is keyed
  # against `0400` and the configuration file's group against `root`, and the two
  # records sit on two machines so that each statement is observed against the
  # other's key.
  testAStatedValueThatDiffersFromTheDefaultMovesTheKey =
    let
      deployment =
        {
          file ? { },
          config ? { },
        }:
        planOf {
          instances = {
            holder = placedOn [ "one" ] (soleRoot {
              module = _: {
                vars.token.files."key" = {
                  secrecy = "secret";
                }
                // file;
                impl =
                  { vars, ... }:
                  {
                    units.only = {
                      command = "/bin/true";
                      env.KEYFILE = vars.token."key".path;
                    };
                  };
              };
            });
            writer = placedOn [ "two" ] (soleRoot {
              module = ownedFileAt config;
            });
          };
          varsState."holder:vars/token@one"."key".present = true;
        };
      plain = deployment { };
      moded = deployment { file.mode = "0440"; };
      grouped = deployment { config.group = "borg"; };
      movedBy =
        other: filter (key: other.plan.${key}.key != plain.plan.${key}.key) (attrNames plain.plan);
    in
    {
      expr = {
        rows = rowIds moded ++ rowIds grouped;
        recordsHeld = [
          moded.plan."holder:vars/token@one".files."key".mode
          grouped.plan."writer:only@two".configData."/etc/thing.conf".group
        ];
        keyspaceHeld = [
          (attrNames moded.plan == attrNames plain.plan)
          (attrNames grouped.plan == attrNames plain.plan)
        ];
        movedByTheMode = movedBy moded;
        movedByTheGroup = movedBy grouped;
      };
      expected = {
        rows = [ ];
        recordsHeld = [
          "0440"
          "borg"
        ];
        keyspaceHeld = [
          true
          true
        ];
        movedByTheMode = [ "holder:vars/token@one" ];
        movedByTheGroup = [ "writer:only@two" ];
      };
    };

  testAnOwnershipThatFailsItsType =
    let
      id = "config-file-ownership-malformed";
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = ownedFileAt { owner = "Postgres Admin"; };
        });
      };
      record = result.plan."svc:only@one".configData."/etc/thing.conf";
    in
    {
      expr = {
        rows = rowIds result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "the module of `only`"
          "`/etc/thing.conf`"
          "`owner`"
        ];
        namesTheType = hasInfix "userName" (said evidenceById id result);
        owner = record.owner;
      };
      expected = {
        rows = [ id ];
        names = [
          true
          true
          true
        ];
        namesTheType = true;
        owner = "root";
      };
    };

  testAUnitThatCannotOpenItsOwnConfigurationFile =
    let
      id = "entry-config-file-unreadable-by-user";
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = ownedFileAt { asUser = "app"; };
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "unit `only`"
          "`app`"
          "`/etc/thing.conf`"
          "`root:root`"
          "`0440`"
        ];
        resolutionNamesBoth = map (needle: hasInfix needle (said resolutionById id result)) [
          "declare `owner`, `group` or `mode`"
          "run the unit as `root`"
        ];
      };
      expected = {
        rows = [ id ];
        severity = "error";
        subjects = [ "svc:only@one" ];
        names = [
          true
          true
          true
          true
          true
        ];
        resolutionNamesBoth = [
          true
          true
        ];
      };
    };

  testAUnitAdmittedByTheFilesGroup =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = ownedFileAt {
            asUser = "app";
            group = "app";
            groups = [ "app" ];
          };
        });
      };
      record = result.plan."svc:only@one".configData."/etc/thing.conf";
    in
    {
      expr = {
        rows = rowIds result;
        group = record.group;
        mode = record.mode;
      };
      expected = {
        rows = [ ];
        group = "app";
        mode = "0440";
      };
    };

  testAUnitThatDeclaresNoAccount =
    let
      result = planOf {
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = ownedFileAt { };
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        unitDeclaresNoUser = result.plan."svc:only@one".units.only ? user;
        mode = result.plan."svc:only@one".configData."/etc/thing.conf".mode;
      };
      expected = {
        rows = [ ];
        unitDeclaresNoUser = false;
        mode = "0440";
      };
    };

  testTwoEntriesSharingADirectoryDeclaredThroughTheVocabulary =
    let
      id = "entry-unit-directory-shared";
      result = planOf {
        instances.svc = membersOn "one" {
          first = declaresDirectory "runtimeDirectory" "records";
          second = declaresDirectory "runtimeDirectory" "records";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`svc:first@one`"
          "`svc:second@one`"
          "`one`"
          "`runtimeDirectory/records`"
        ];
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        severity = "warning";
        subjects = [ "svc:first@one" ];
        names = [
          true
          true
          true
          true
        ];
        applicable = true;
      };
    };

  testAStateDirectoryAndARuntimeDirectoryOfOneName =
    let
      result = planOf {
        instances.svc = membersOn "one" {
          first = declaresDirectory "stateDirectory" "records";
          second = declaresDirectory "runtimeDirectory" "records";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        recorded = [
          result.plan."svc:first@one".units.only.stateDirectory
          result.plan."svc:second@one".units.only.runtimeDirectory
        ];
      };
      expected = {
        rows = [ ];
        recorded = [
          [ "records" ]
          [ "records" ]
        ];
      };
    };

  testAMachineThatReservesAPortKeysAsItDid =
    let
      planWith =
        machines:
        planOf {
          inherit machines;
          instances.svc = placedOn [ "one" ] (soleRoot {
            module = holdsAValue;
          });
          varsState."svc:vars/hostKey@one"."key".present = true;
        };
      plain = planWith support.machines;
      reserved = planWith (
        reserving "one" {
          ports.sshd = {
            proto = "tcp";
            number = 22;
          };
          paths = [ "/etc/ssh/sshd_config" ];
        }
      );
    in
    {
      expr = {
        rows = rowIds plain ++ rowIds reserved;
        planned = [
          (attrNames plain.plan)
          (attrNames reserved.plan)
        ];
        moved = filter (key: plain.plan.${key}.key != reserved.plan.${key}.key) (attrNames plain.plan);
        keys = keysOf reserved;
      };
      expected = {
        rows = [ ];
        planned = [
          [
            "machine:one"
            "svc:only@one"
            "svc:vars/hostKey@one"
          ]
          [
            "machine:one"
            "svc:only@one"
            "svc:vars/hostKey@one"
          ]
        ];
        moved = [ ];
        keys = {
          "machine:one" = "sha256-565f8656738015bf";
          "svc:only@one" = "sha256-65f61292e813b2c7";
          "svc:vars/hostKey@one" = "sha256-590e2fae1cb98d5a";
        };
      };
    };

  testAMachineReservesAPortAnEntryClaims =
    let
      id = "entry-port-claimed-twice";
      result = planOf {
        machines = reserving "one" {
          ports.sshd = {
            proto = "tcp";
            number = 22;
          };
        };
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = claimsPort "tcp" 22 null;
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        count = countById id result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`machine:one`"
          "`svc:only@one`"
          "the port `22` on protocol `tcp`"
          "machine `one`"
        ];
        resolutionNamesBothDeclarations = map (needle: hasInfix needle (said resolutionById id result)) [
          "`fixed` port other than `22`"
          "`reserves.ports` of machine `one`"
        ];
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        count = 1;
        severity = "error";
        subjects = [ "machine:one" ];
        names = [
          true
          true
          true
          true
        ];
        resolutionNamesBothDeclarations = [
          true
          true
        ];
        applicable = false;
      };
    };

  testAMachineReservesAPathAnEntryWrites =
    let
      id = "entry-host-path-claimed-twice";
      result = planOf {
        machines = reserving "one" { paths = [ "/etc/x.conf" ]; };
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = writesTo "/etc/x.conf";
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`machine:one`"
          "`svc:only@one`"
          "`/etc/x.conf`"
          "machine `one`"
        ];
        resolutionNamesTheRegistry = hasInfix "`reserves.paths` of machine `one`" (
          said resolutionById id result
        );
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        severity = "error";
        subjects = [ "machine:one" ];
        names = [
          true
          true
          true
          true
        ];
        resolutionNamesTheRegistry = true;
        applicable = false;
      };
    };

  testAMachineAndTwoEntriesClaimOnePort =
    let
      id = "entry-port-claimed-twice";
      result = planOf {
        machines = reserving "one" {
          ports.resolved = {
            proto = "tcp";
            number = 5432;
          };
        };
        instances.svc = membersOn "one" {
          alpha = claimsPort "tcp" 5432 null;
          beta = claimsPort "tcp" 5432 null;
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        count = countById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`machine:one`"
          "`svc:alpha@one`"
          "`svc:beta@one`"
        ];
      };
      expected = {
        rows = [ id ];
        count = 1;
        subjects = [ "machine:one" ];
        names = [
          true
          true
          true
        ];
      };
    };

  testAMachineReservesAPortNothingClaims =
    let
      result = planOf {
        machines = reserving "one" {
          ports.sshd = {
            proto = "tcp";
            number = 22;
          };
          paths = [ "/etc/ssh/sshd_config" ];
        };
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = claimsPort "tcp" 5432 null;
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        applicable = true;
      };
    };

  # The machine the reservation is on runs nothing, so it is in no plan and can
  # be the subject of nothing. The claim it would have made is one an entry on
  # the other machine makes.
  testAReservationOnAMachineNoPlacementSelects =
    let
      result = planOf {
        machines = reserving "two" {
          ports.listen = {
            proto = "tcp";
            number = 5432;
          };
          paths = [ "/etc/x.conf" ];
        };
        instances.svc = membersOn "one" {
          alpha = claimsPort "tcp" 5432 null;
          beta = writesTo "/etc/x.conf";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        planned = attrNames result.plan;
        subjectedToIt = filter (row: row.subject == "machine:two") result.diagnostics;
      };
      expected = {
        rows = [ ];
        planned = [
          "machine:one"
          "svc:alpha@one"
          "svc:beta@one"
        ];
        subjectedToIt = [ ];
      };
    };

  testAReservedPortAndAClaimOnAnotherProtocol =
    let
      result = planOf {
        machines = reserving "one" {
          ports.listen = {
            proto = "udp";
            number = 5432;
          };
        };
        instances.svc = placedOn [ "one" ] (soleRoot {
          module = claimsPort "tcp" 5432 null;
        });
      };
    in
    {
      expr = {
        rows = rowIds result;
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        applicable = true;
      };
    };

  testTheEntryRecordsTheNumberAlone =
    let
      result = planOf {
        instances.svc = membersOn "one" {
          only = claimsPort "tcp" 5432 "10.0.0.11";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        alloc = result.plan."svc:only@one".alloc;
      };
      expected = {
        rows = [ ];
        alloc.ports.listen = 5432;
      };
    };

  testAClaimThatStatesAnAddressKeysAsItDid =
    let
      keyOf =
        address:
        (planOf {
          instances.svc = membersOn "one" {
            only = claimsPort "tcp" 5432 address;
          };
        }).plan."svc:only@one".key;
      unstated = planOf {
        instances.svc = membersOn "one" {
          only = claimsPort "tcp" 5432 null;
        };
      };
      stated = planOf {
        instances.svc = membersOn "one" {
          only = claimsPort "tcp" 5432 "one.example";
        };
      };
    in
    {
      expr = {
        rows = [
          (rowIds unstated)
          (rowIds stated)
        ];
        keysAreOneKey = keyOf null == keyOf "one.example";
      };
      expected = {
        rows = [
          [ ]
          [ ]
        ];
        keysAreOneKey = true;
      };
    };

  # The address reaches the claim through the member's settings, and those are an
  # input to the key already, so the entry re-keys and its sibling does not.
  testAnAddressADeploymentMovesReKeysThroughSettings =
    let
      deployment =
        address:
        planOf {
          instances.svc = {
            module =
              { service, ... }:
              {
                services.bound = service "bound" {
                  module = claimsFromSetting;
                  defaults.address = "10.0.0.11";
                };
                services.other = service "other" { module = writesTo "/etc/other.conf"; };
              };
            placement.every = {
              bound.machines = [ "one" ];
              other.machines = [ "one" ];
            };
            settings.bound.address = address;
          };
        };
      before = deployment "10.0.0.11";
      after = deployment "10.0.0.12";
      keyOf = result: member: result.plan."svc:${member}@one".key;
    in
    {
      expr = {
        rows = [
          (rowIds before)
          (rowIds after)
        ];
        boundMoved = keyOf before "bound" != keyOf after "bound";
        siblingStayed = keyOf before "other" == keyOf after "other";
      };
      expected = {
        rows = [
          [ ]
          [ ]
        ];
        boundMoved = true;
        siblingStayed = true;
      };
    };

  testOneClaimStatesAProtocolAndTheOtherStatesNone =
    let
      id = "entry-port-claimed-twice";
      result = planOf {
        instances.svc = membersOn "one" {
          first = claimsPort "tcp" 5432 null;
          second = claimsPort null 5432 null;
        };
      };
      twoProtocols = planOf {
        instances.svc = membersOn "one" {
          first = claimsPort "tcp" 5432 null;
          second = claimsPort "udp" 5432 null;
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        count = countById id result;
        severity = severityById id result;
        namesTheNarrowerProtocol = hasInfix "protocol `tcp`" (said messageById id result);
        twoProtocolsOfTheDomain = rowIds twoProtocols;
        applicable = [
          result.applicable
          twoProtocols.applicable
        ];
      };
      expected = {
        rows = [ id ];
        count = 1;
        severity = "error";
        namesTheNarrowerProtocol = true;
        twoProtocolsOfTheDomain = [ ];
        applicable = [
          false
          true
        ];
      };
    };

  testTwoClaimsOfOneNumberBindTwoAddresses =
    let
      result = planOf {
        instances.svc = membersOn "one" {
          first = claimsPort "tcp" 5432 "10.0.0.11";
          second = claimsPort "tcp" 5432 "10.0.0.12";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        applicable = result.applicable;
        allocated = map (key: result.plan.${key}.alloc.ports.listen) [
          "svc:first@one"
          "svc:second@one"
        ];
      };
      expected = {
        rows = [ ];
        applicable = true;
        allocated = [
          5432
          5432
        ];
      };
    };

  testAWildcardClaimAndASpecificClaimOfOneNumber =
    let
      id = "entry-port-claimed-twice";
      result = planOf {
        instances.svc = membersOn "one" {
          first = claimsPort "tcp" 5432 null;
          second = claimsPort "tcp" 5432 "10.0.0.11";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        count = countById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (said messageById id result)) [
          "`svc:first@one`"
          "`svc:second@one`"
          "`5432`"
          "address `10.0.0.11`"
        ];
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        count = 1;
        subjects = [ "svc:first@one" ];
        names = [
          true
          true
          true
          true
        ];
        applicable = false;
      };
    };

  # A refused protocol is read as unstated, which is the wider reading: the
  # deployment carrying the refusal is not checked less than one carrying none.
  testARefusedProtocolCollidesWithEveryProtocol =
    let
      id = "entry-port-claimed-twice";
      result = planOf {
        instances.svc = membersOn "one" {
          first = claimsPort "TCP" 5432 null;
          second = claimsPort "udp" 5432 null;
        };
      };
    in
    {
      expr = {
        rows = sortStrings (rowIds result);
        count = countById id result;
        namesTheStatedProtocol = hasInfix "protocol `udp`" (said messageById id result);
      };
      expected = {
        rows = [
          "entry-port-claimed-twice"
          "port-claim-protocol-unknown"
        ];
        count = 1;
        namesTheStatedProtocol = true;
      };
    };

  # A field enters a key only where its value differs from the default it would
  # resolve to unstated, and neither of these has one, so a unit declaring
  # neither carries neither and keys exactly as it did before the vocabulary
  # grew. The other half is that stating one does move the key: a changed probe
  # is a new generation and a new image.
  testAnEntryThatDeclaresNoProbeKeepsItsKey =
    let
      bare = support.entryPlan { } (_: {
        units.web.command = "/bin/web";
      });
      probed = support.entryPlan { } (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
        };
      });
      entry = bare.plan."svc:only@one";
    in
    {
      expr = {
        rows = rowIds bare;
        fields = attrNames entry.units.web;
        keyMentionsAProbe = hasInfix "probe" (toJSON entry.units);
        statingOneMovesTheKey = entry.key != probed.plan."svc:only@one".key;
      };
      expected = {
        rows = [ ];
        fields = [ "command" ];
        keyMentionsAProbe = false;
        statingOneMovesTheKey = true;
      };
    };

  # The plan is a function of a declaration and health is a fact about a running
  # machine, so the record carries the command and the bound and no third field:
  # a health, readiness or liveness state would be the planner restating an
  # answer it cannot have, and whether the probe is enabled is a realiser's.
  testThePlanSaysHowToProbeAndNeverWhetherItIsHealthy =
    let
      result = support.entryPlan { } (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
        };
      });
      # The names the plan carries and not its text: a probe's own command is a
      # word the deployment chose, and refusing a plan because a module called
      # its program `web-ready` would be reading a declaration's vocabulary as
      # the planner's.
      namesDeep =
        value:
        if isAttrs value then
          concatLists (map (name: [ name ] ++ namesDeep value.${name}) (attrNames value))
        else if isList value then
          concatLists (map namesDeep value)
        else
          [ ];
      fields = namesDeep result.plan;
      carries = needle: any (name: hasInfix needle name) fields;
    in
    {
      expr = {
        rows = rowIds result;
        recorded = result.plan."svc:only@one".units.web;
        absent = map carries [
          "health"
          "Health"
          "ready"
          "Ready"
          "liveness"
          "Liveness"
          "enabled"
          "Enabled"
        ];
      };
      expected = {
        rows = [ ];
        recorded = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
        };
        absent = [
          false
          false
          false
          false
          false
          false
          false
          false
        ];
      };
    };

  # Which file a realiser derives for a probe is the realiser's; the plan records
  # the units the module declared and rewrites no reference between them.
  testAProbeAddsNoUnitToThePlan =
    let
      result = support.entryPlan { } (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
          requires = [ "socket" ];
        };
        units.socket.command = "/bin/socket";
      });
      entry = result.plan."svc:only@one";
    in
    {
      expr = {
        rows = rowIds result;
        units = sortStrings (attrNames entry.units);
        requires = entry.units.web.requires;
        socket = attrNames entry.units.socket;
      };
      expected = {
        rows = [ ];
        units = [
          "socket"
          "web"
        ];
        requires = [ "socket" ];
        socket = [ "command" ];
      };
    };
}
