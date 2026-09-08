# The plan artifact: entries, keys, planes, absence and the two files a value
# can land in, plus the committed plan the worked folder carries.
#
# One test per scenario of specs/planner/plan-artifact/spec.md that is about the
# shape of the artifact, named after that scenario. The golden comparison is
# here rather than in a Python suite because the fixture no longer carries prose
# the plan does not: every field participates, `==` is the comparison, and the
# difference function below reports the attribute paths that differ rather than
# two documents (design.md D6). The prose those `note` keys held is beside the
# fixture, in fixtures/minimal-typed-edge/plan/README.md.
{
  planner,
  support,
  folder,
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

  # ------------------------------------------------------ the golden fixture --

  fixture = fromJSON (readFile (folder + "/plan/backup.json"));

  join = path: name: if path == "" then name else "${path}.${name}";

  # One dotted path per difference. A missing field, an extra field and a
  # changed value are three sentences about the same path, so a drifted field
  # names itself and no other entry is printed.
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

  # A fixture is worth committing only if it is the real thing: an ellipsis or a
  # hash that is not sixteen hex digits is a value somebody typed.
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

  # Every entry key the fixture names anywhere inside itself: in a dependency
  # list, a reader list, a row subject or the entries of a set-valued read. A
  # fixture that elided an entry would still name it in one of those places.
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

  # One entry drifted, so the difference function is asserted on a difference
  # rather than only on their being none.
  drifted =
    key: field: value:
    fixture
    // {
      ${key} = fixture.${key} // {
        ${field} = value;
      };
    };

  # ------------------------------------------- the committed rendered table --

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

  # A header is `  ! <subject>  <message>`; the message continues on any line
  # indented past the detail columns, and the severity is the first word of the
  # `severity:` detail below it.
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

  # A literal store path, so an entry has a closure without anything being
  # realised. The worked deployment's own two packages are the same strings.
  inherit (support.worked) openssh;

  # `"<planKey>@<keyHash>"` split at the LAST `@`, because a plan key carries
  # one of its own: `machine:alpha@sha256-…` and `i:only@one@sha256-…` are both
  # read the same way.
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

  # The same, with the knobs the deployment moves. A single-member root keys its
  # settings namespace under the member's own name, including when it owns one.
  placedWith =
    machines: knobs: module:
    (placedOn machines module) // { settings.only = knobs; };

  keysOf = result: mapAttrs (_: entry: entry.key) result.plan;
in
{
  # The plan is data: it round-trips through JSON, which is what makes it the
  # only thing the two halves of the architecture have to agree on.
  testThePlanSerialises = {
    expr = {
      roundTrips = fromJSON (toJSON workedPlan) == workedPlan;
      entryCount = length (attrNames workedPlan);
    };
    expected = {
      roundTrips = true;
      entryCount = 8;
    };
  };

  # One service on two machines: two entries whose keys differ only in the
  # machine, carrying the same units and the same placement record and a
  # different hash and a different machine dependency.
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

  # Every dependency of the worked plan is a key that appears in that same plan,
  # written beside that entry's own key hash.
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
      expected = {
        dependencyCount = 4;
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

  # A setting changed on one service, read by nothing else: the other service's
  # key is what it was and the changed service's key is not.
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

  # A provider's exported value changes and the consumer reads it into a unit's
  # environment: the consumer is re-keyed, and its closure is not touched
  # because the value arrived on the environment plane.
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

  # A machine gains the tag that decides the membership of a set-valued read:
  # the set names one more entry, the reading entry is re-keyed, and the warning
  # that says so is in the table. Task 6.7.
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

  # gamma's generator has not run. The reading entry names that placement with a
  # null value, an explicit absence marker and the row the absence produced,
  # rather than dropping it from the set.
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

  # The authorized-keys file is rendered from that same set: it is recorded as
  # not computed, with neither a hash nor a recipe assembled from the two
  # entries that do have values, and it still names the unit the module wrote
  # for reloading.
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

  # A service generating a keypair and using the private half in its own unit:
  # the plan carries the path and the bytes appear nowhere in it, not in the
  # export, not in the unit's environment and not in the vars record. Task 6.5.
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
        varsState.one.hostKey = {
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
        # The same search over the public half, which the plan does carry: the
        # negative above is a fact about the private bytes and not about the
        # search.
        publicBytesInThePlan = hasInfix "ssh-ed25519 PUBLICHALF" (toJSON result.plan);
        publicHalf = entry.provides.identity.exports.publicKey.value;
        rows = result.diagnostics;
      };
      expected = {
        privateHalf = {
          plane = "reference";
          readBy = [ ];
          secrecy = "secret";
          value = "/run/vars/hostKey/ssh_host_ed25519_key";
        };
        env.KEYFILE = "/run/vars/hostKey/ssh_host_ed25519_key";
        varsRecord = {
          inPlan = "reference";
          path = "/run/vars/hostKey/ssh_host_ed25519_key";
          secrecy = "secret";
        };
        bytesAnywhereInThePlan = false;
        publicBytesInThePlan = true;
        publicHalf = "ssh-ed25519 PUBLICHALF";
        rows = [ ];
      };
    };

  # The worked deployment's private half is read by no slot, because no slot may
  # name it: it is recorded with an empty reader list beside the public half's
  # one reader.
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
        value = "/run/vars/hostKey/ssh_host_ed25519_key";
      };
      publicHalfReadBy = [ "vault-repo:server@vault" ];
    };
  };

  # The content of a rendered configuration file changes: the entry records the
  # new hash and the units to reload, and its closure is what it was, because a
  # file on the reload plane is not part of it.
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

  # A value a unit reads from its environment changes: the key changes and the
  # closure does not, because the environment is hashed and the store paths the
  # entry names have not moved.
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

  # Task 6.2. Two evaluations of one input produce equal keys, entry for entry,
  # which is what makes a plan comparable across runs at all.
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
        keyCount = 8;
      };
    };

  # Task 6.1. A service no placement selected runs nowhere: its entry carries no
  # machine in its key, no closure and nothing it depends on, and no machine
  # entry is invented for it.
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

  # A machine's address is a key input, because a module may render a unit out
  # of it: the entries on that machine are re-keyed and the entries on every
  # other machine are not. Nothing else about the plan moves with it — the
  # placements, the allocations and the wires are the same plan.
  #
  # The wire here carries a constant rather than the producer's address, so
  # "every other entry's key is unchanged" is about the address alone. A
  # consumer that read the address would be re-keyed by the value it read,
  # which is the rule of testAReadValueChangesTheReadersKey.
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

  # The committed plan is the produced plan. Every field participates, because
  # the fixture carries nothing the planner did not write.
  testTheGoldenPlanMatches = {
    expr = {
      difference = differences workedPlan;
      entries = length (attrNames fixture);
      typedByHand = placeholders fixture;
    };
    expected = {
      difference = [ ];
      entries = 8;
      typedByHand = [ ];
    };
  };

  # A drifted field names its own attribute path and nothing else: a reader is
  # told which entry and which field, not handed two documents.
  testAGoldenFixtureDrifts = {
    expr = differencesAt "" (drifted "vault-repo:server@vault" "key"
      "sha256-0000000000000000"
    ) workedPlan;
    expected = [ "vault-repo:server@vault.key: differs" ];
  };

  # An ellipsis or a hand-invented hash is a value somebody typed, and a fixture
  # that carries one has stopped being evidence.
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

  # Every entry the fixture names anywhere is an entry the fixture carries.
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
        "vault-repo:server@vault"
      ];
    };
  };

  # The rows the folder's own prose attributes to this deployment are the rows
  # the planner produces, and each one's message is in the rendered table.
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
}
