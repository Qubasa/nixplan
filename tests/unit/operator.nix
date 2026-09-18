{
  planner,
  support,
  operatorSource,
  imageSource,
  flakeletSource,
}:
let
  inherit (builtins)
    all
    attrNames
    filter
    isString
    length
    toJSON
    ;

  inherit (support)
    hasInfix
    planOf
    pub
    root
    soleRoot
    ;

  inherit (support.worked) borgbackup openssh;

  realiser = support.realiser {
    inherit imageSource flakeletSource operatorSource;
  };

  inherit (realiser) imageReader flakeletReader;

  reader = realiser.operatorReader;

  sorted = builtins.sort (a: b: a < b);

  simple = support.serving "only";

  # A machine deployed as an account rather than as root. `scope` enters the
  # machine record only where it is `user`, so this registry is the whole fact
  # the crossing reads.
  userScoped = {
    registry = support.machines // {
      account = support.machines.one // {
        address = "account.example:22";
        scope = "user";
      };
    };
    machine = "account";
  };

  onAnAccount = realiser.planned userScoped simple;

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

  deployment = implementation: (realiser.planned { } implementation).result;

  # A configuration file whose recipe reads a delivered path: its bytes exist on
  # no machine until that path is written, which is the one host path the default
  # realiser still runs no step for.
  refBearing = support.valuePlan {
    extra = vars: {
      configData."/etc/agent.conf" = {
        mode = "0400";
        reload = [ "only" ];
        render = [
          { text = "key_file = "; }
          { ref = vars.hostKey."key".path; }
        ];
      };
    };
  };

  # An extension the library accepts and no realiser's directive table names.
  unrenderedExtension = planner.unitExtension {
    backend = "systemd";
    name = "exotic";
    fields.blockIODeviceWeight.type = support.korora.string;
  };

  extendedBeyondTheTable = _: {
    closure = [ borgbackup ];
    units.only = {
      command = "${borgbackup}/bin/borg serve";
      extends = [
        {
          extension = unrenderedExtension;
          values.blockIODeviceWeight = "/dev/sda 500";
        }
      ];
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

  # The one statement most of these readings make: the image realiser under a
  # profile, for every entry the deployment places.
  underImage =
    profile:
    readOf {
      default = {
        realiser = "image";
        inherit profile;
      };
    };

  # A realiser's reading of one entry, forced, so `success` answers whether the
  # refusal the row above it predicts was made.
  forced =
    read: args:
    builtins.tryEval (
      let
        artifact = read args;
      in
      builtins.deepSeq artifact artifact
    );

  worked = support.workedResult;

  # The fixture's `vault-repo:server` assembles a configuration file, which is
  # the one thing the default realiser runs no step for, so the worked reading
  # states an image for it.
  workedRealise."vault-repo:server" = {
    realiser = "image";
    profile = "trusted";
  };

  workedRead = reader.read {
    inherit (worked) plan;
    realise = workedRealise;
  };

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

  unitNamed = unit: _: {
    closure = [ borgbackup ];
    units.${unit}.command = "${borgbackup}/bin/borg serve";
  };

  # One unit that says how it is probed, named by the caller so a test can have
  # the declared unit spell the entry's own derived probe file or not.
  probedUnit = unit: _: {
    closure = [ borgbackup ];
    units.${unit} = {
      command = "${borgbackup}/bin/borg serve";
      probe = "${borgbackup}/bin/borg check";
      probeTimeout = "30s";
    };
  };

  # Two instances whose service names both flatten to `a-b-c`, each probed and
  # each declaring a unit of its own name: the declared unit files differ and the
  # two derived probe files are one file on one machine, which is the namespace
  # question the existing index owns.
  sharingAProbeFile = planOf {
    instances = {
      "a-b" = {
        module = root { members.c.module = _: { impl = probedUnit "first"; }; };
        placement.every.c.machines = [ "one" ];
      };
      a = {
        module = root { members."b-c".module = _: { impl = probedUnit "second"; }; };
        placement.every."b-c".machines = [ "one" ];
      };
    };
  };

  # Two members of one instance whose artifact names differ and whose derived
  # unit file names do not: `a:b` declaring `c-main` and `a:b-c` declaring
  # `main` both spell `a-b-c-main.service` on `one`.
  sharingAUnitFile = planOf {
    instances.a = {
      module = root {
        members.b.module = _: { impl = unitNamed "c-main"; };
        members."b-c".module = _: { impl = unitNamed "main"; };
      };
      placement.every.b.machines = [ "one" ];
      placement.every."b-c".machines = [ "one" ];
    };
  };

  # The same two members, one unit name apart.
  distinctUnitFiles = planOf {
    instances.a = {
      module = root {
        members.b.module = _: { impl = unitNamed "main"; };
        members."b-c".module = _: { impl = unitNamed "main"; };
      };
      placement.every.b.machines = [ "one" ];
      placement.every."b-c".machines = [ "one" ];
    };
  };

  # A configuration file the planner refused for its missing `mode`, which it
  # records as none: the entry is planned and its record states no account.
  modeless = _: {
    closure = [ borgbackup ];
    units.only.command = "${borgbackup}/bin/borg serve";
    configData."/etc/agent.conf" = {
      reload = [ "only" ];
      render = [ { text = "listen = yes\n"; } ];
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
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };

  # A configuration file whose record a store object cannot carry: its bytes are
  # literals the builder writes, so the only thing wrong with it is the account
  # the declaration opens it to.
  ownedConfigFile = _: {
    closure = [ borgbackup ];
    units.only.command = "${borgbackup}/bin/borg serve";
    configData."/etc/agent.conf" = {
      owner = "postgres";
      group = "postgres";
      mode = "0440";
      reload = [ "only" ];
      render = [ { text = "listen = yes\n"; } ];
    };
  };

  # A generator declaring no files, planned rather than written out: the plan is
  # what the planner produces, and the pruned copy beside it is the plan a reader
  # written before `files` was always recorded would be handed.
  fileless = planOf {
    instances.holder = {
      module = soleRoot {
        module = _: {
          vars.app = { };
          impl = simple;
        };
      };
      placement.every.only.machines = [ "one" ];
    };
  };

  filelessValue = "holder:vars/app@one";

  without =
    plan: key: field:
    plan // { ${key} = builtins.removeAttrs plan.${key} [ field ]; };

  # Two well-formed age native recipients, which is all the reading ever sees:
  # a line the atom refused is left out of every projection, so no malformed one
  # can reach here.
  recipient = "age1qpzry9x8gf2tvdw0s3jn54khce6mua7lqpzry9x8gf2tvdw0s3jn54khce";
  rotated = "age1xv4fk5knx0prhznxn4v9z5lm672mesxe2hunguwymdam8u34xyyq67ekjr";

  tokenFile = {
    path = "/run/vars/issuer/session/token";
    secrecy = "secret";
    owner = "nobody";
    group = "nogroup";
    mode = "0440";
  };

  # The per-machine reading is a function of the plan, so the conditions it
  # answers are written out as one: `alpha` seals and receives, `beta` receives
  # and declares no recipient, `delta` seals and receives a value of its own,
  # and `gamma` seals, runs an entry and is in no delivery set. The recipient
  # and one file's mode are arguments so that a rotation and a change to one
  # machine's values can each be read against the same baseline.
  deliveredPlan =
    { seal, mode }:
    {
      "machine:alpha" = {
        address = "alpha.example";
        tags = [ ];
        sealRecipient = seal;
      };
      "machine:beta" = {
        address = "beta.example";
        tags = [ ];
        sealRecipient = null;
      };
      "machine:delta" = {
        address = "delta.example";
        tags = [ ];
        sealRecipient = seal;
      };
      "machine:gamma" = {
        address = "gamma.example";
        tags = [ ];
        sealRecipient = seal;
      };
      "issuer:vars/session@alpha" = {
        delivery = [
          "alpha"
          "beta"
        ];
        deliveryDerivedFrom = [ ];
        files.token = tokenFile;
      };
      "keeper:vars/store@delta" = {
        delivery = [ "delta" ];
        deliveryDerivedFrom = [ ];
        files.blob = {
          path = "/run/vars/keeper/store/blob";
          secrecy = "secret";
          owner = "root";
          group = "root";
          inherit mode;
        };
      };
      "issuer:api@gamma" = {
        key = "sha256-0000000000000000";
        placement.reason = "every";
        units.only.command = "/bin/true";
      };
    };

  delivered = reader.read {
    plan = deliveredPlan {
      seal = recipient;
      mode = "0400";
    };
  };

  # One machine, one value, and three entries on it: one whose unit names the
  # value's path, one whose own configuration file's recipe names it, and one
  # that names no value at all.
  orderedPlan = {
    "machine:alpha" = {
      address = "alpha.example";
      tags = [ ];
      sealRecipient = recipient;
    };
    "issuer:vars/session@alpha" = {
      delivery = [ "alpha" ];
      deliveryDerivedFrom = [ ];
      files.token = tokenFile;
    };
    "watch:reader@alpha" = {
      key = "sha256-0000000000000001";
      placement.reason = "every";
      units.fetch = {
        command = "/bin/true";
        env.TOKEN = tokenFile.path;
      };
    };
    "watch:owner@alpha" = {
      key = "sha256-0000000000000002";
      placement.reason = "every";
      units.load.command = "/bin/true";
      configData."/etc/agent.conf" = {
        owner = "root";
        group = "root";
        mode = "0400";
        render = [ { ref = tokenFile.path; } ];
      };
    };
    "watch:idle@alpha" = {
      key = "sha256-0000000000000003";
      placement.reason = "every";
      units.tick.command = "/bin/true";
    };
  };

  # A machine deployed as an account: `scope` enters the machine record only
  # where it is `user`, so this record is the whole fact the reading crosses.
  onAccountPlan = {
    "machine:account" = {
      address = "account.example";
      tags = [ ];
      scope = "user";
      sealRecipient = recipient;
    };
    "issuer:vars/session@account" = {
      delivery = [ "account" ];
      deliveryDerivedFrom = [ ];
      files.token = tokenFile;
    };
  };

  # The separators of one derived unit file name, counted: `split` answers the
  # pieces and the matches alternately, so one hyphen is two extra elements.
  hyphens = name: (builtins.length (builtins.split "-" name) - 1) / 2;

  inherit (realiser) idsOf rowsById;
in
{
  testAValueEntryRecordsNoFiles =
    let
      recorded = fileless.plan.${filelessValue};
      pruned = without fileless.plan filelessValue "files";
      reading = reader.read { plan = pruned; };
      row = builtins.head (rowsById "operator-plan-field-missing" reading);
    in
    {
      expr = {
        # The planner records the empty set rather than pruning it away.
        plannerRecordsIt = recorded ? files;
        plannerRecordsItEmpty = recorded.files;
        rows = idsOf reading;
        subject = row.subject;
        namesTheField = hasInfix "`files`" row.message;
        # The rest of the plan is still read.
        entries = attrNames reading.manifest.entries;
        values = attrNames reading.manifest.values;
        files = reading.manifest.values.${filelessValue}.files;
        # The table names the value entry itself: a value key is a plan key, so
        # it survives the subject discipline whole.
        tableSubjects = map (r: r.subject) reading.diagnostics;
      };
      expected = {
        plannerRecordsIt = true;
        plannerRecordsItEmpty = { };
        rows = [ "operator-plan-field-missing" ];
        subject = filelessValue;
        namesTheField = true;
        entries = [ "holder:only@one" ];
        values = [ filelessValue ];
        files = { };
        tableSubjects = [ filelessValue ];
      };
    };

  testAFieldThePlanOmitsIsNeededByTheReading =
    let
      key = "issuer:vars/session@alpha";
      plan = {
        "machine:alpha" = {
          address = "alpha.example";
          tags = [ ];
        };
        ${key} = {
          delivery = [ "alpha" ];
          deliveryDerivedFrom = [ ];
          files.token = {
            path = "/run/vars/issuer/session/token";
          };
        };
      };
      reading = reader.read { inherit plan; };
      row = builtins.head (rowsById "operator-plan-field-missing" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        namesTheEntry = row.subject;
        namesTheField = hasInfix "`secrecy`" row.message;
        namesWhere = hasInfix "`token`" row.message;
        severity = row.severity;
        # A table, not an evaluation error, and the record is still published.
        table = builtins.length reading.diagnostics;
        recorded = reading.manifest.values.${key}.files.token;
      };
      expected = {
        # One row per field the record owes the command: the secrecy and the
        # three the write reads.
        rows = [
          "operator-plan-field-missing"
          "operator-plan-field-missing"
          "operator-plan-field-missing"
          "operator-plan-field-missing"
        ];
        namesTheEntry = key;
        namesTheField = true;
        namesWhere = true;
        severity = "error";
        table = 4;
        recorded = {
          path = "/run/vars/issuer/session/token";
          sealed = "/var/lib/planner/sealed/issuer/session/token.age";
          secrecy = "";
          owner = "";
          group = "";
          mode = "";
        };
      };
    };

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
        # Two keys that project onto one artifact name also derive one unit file
        # name, and the two are two facts: one directory cannot hold two
        # entries, and one machine cannot hold two unit files of one name.
        ids = [
          "operator-entry-name-collision"
          "operator-entry-unit-file-collision"
        ];
        count = 1;
        subject = "a-b:c@one";
        namesBoth = true;
        namesTheName = true;
        refused = true;
      };
    };

  # The unit file names both realisers derive are one namespace per machine, and
  # the artifact name beside them carries the machine, so it cannot see a
  # collision inside one. The row is the shared reading's, which is why one pair
  # of entries earns the same row under either statement.
  testAUnitFileNameCollisionIsReportedUnderEitherRealiser =
    let
      asImage = underImage "trusted";
      asService = readOf { default.realiser = "flakelet"; };
      imaged = asImage sharingAUnitFile;
      served = asService sharingAUnitFile;
      row = builtins.head (rowsById "operator-entry-unit-file-collision" served);
      derived = key: served.manifest.entries.${key}.units;
    in
    {
      expr = {
        ids = idsOf served;
        underEitherRealiser = idsOf imaged == idsOf served;
        theSameRow = rowsById "operator-entry-unit-file-collision" imaged == [ row ];
        subject = row.subject;
        namesBoth = hasInfix "`a:b-c@one`, `a:b@one`" row.message;
        namesTheFile = hasInfix "`a-b-c-main.service`" row.message;
        namesTheMachine = hasInfix "`one`" row.message;
        # The name is derived rather than stated, so the two entries spend one
        # file name whichever realiser is asked to emit it.
        spent = {
          "a:b@one" = derived "a:b@one";
          "a:b-c@one" = derived "a:b-c@one";
        };
        # The artifact names of the pair differ, so this is the only row: the
        # projection above sees nothing and neither builder is reached.
        artifacts = sorted (
          map (key: served.manifest.entries.${key}.path) (placedOf sharingAUnitFile.plan)
        );
        refused = {
          image = imaged.refused;
          service = served.refused;
        };
        # One unit name apart, and neither reading has anything to say.
        distinct = {
          image = idsOf (asImage distinctUnitFiles);
          service = idsOf (asService distinctUnitFiles);
          refused = (asService distinctUnitFiles).refused;
        };
      };
      expected = {
        ids = [ "operator-entry-unit-file-collision" ];
        underEitherRealiser = true;
        theSameRow = true;
        subject = "a:b-c@one";
        namesBoth = true;
        namesTheFile = true;
        namesTheMachine = true;
        spent = {
          "a:b@one" = [ "a-b-c-main.service" ];
          "a:b-c@one" = [ "a-b-c-main.service" ];
        };
        artifacts = [
          "entries/a-b-c-one"
          "entries/a-b-one"
        ];
        refused = {
          image = true;
          service = true;
        };
        distinct = {
          image = [ ];
          service = [ ];
          refused = false;
        };
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
      row = builtins.head (rowsById "operator-statement-names-nothing" elsewhere);
    in
    {
      expr = {
        unstated = unstated.manifest.entries.${oneKey}.realiser;
        defaulted = defaulted.manifest.entries.${oneKey}.realiser;
        elsewhere = elsewhere.manifest.entries.${oneKey}.realiser;
        profile = unstated.manifest.entries.${oneKey}.profile;
        rows = unstated.rows ++ defaulted.rows;
        # A statement about a key the plan does not carry is a decision nobody
        # applied, so the entry keeps the default realiser and the statement is
        # refused rather than passed over.
        statedElsewhere = {
          ids = idsOf elsewhere;
          subject = row.subject;
          refused = elsewhere.refused;
        };
      };
      expected = {
        unstated = "flakelet";
        defaulted = "flakelet";
        elsewhere = "flakelet";
        profile = null;
        rows = [ ];
        statedElsewhere = {
          ids = [ "operator-statement-names-nothing" ];
          subject = "other:thing";
          refused = true;
        };
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

      # A name every realiser's rule refuses, stated for a realiser there is
      # none of: the statement resolves to no endpoint, so nothing is asked of
      # one and the row naming the statement is the only row.
      refusedName = planOf {
        instances."sv?c" = {
          module = soleRoot { module = _: { impl = simple; }; };
          placement.every.only.machines = [ "one" ];
        };
      };
      unrouted = readOf { default.realiser = "podman"; } refusedName;
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
        askedOfNoEndpoint = idsOf unrouted;
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
        askedOfNoEndpoint = [ "operator-realiser-unknown" ];
      };
    };

  # The statement is a record a caller writes, so it is read for its kind before
  # it is indexed: a realiser of another kind resolves to no endpoint and earns
  # the row an unimplemented name earns, rather than ending the reading.
  testARealisationStatementNamesARealiserOfAnotherKind =
    let
      reading = readOf { default.realiser = 3; } one;
      row = builtins.head (rowsById "operator-realiser-unknown" reading);
    in
    {
      expr = {
        ids = idsOf reading;
        count = length (rowsById "operator-realiser-unknown" reading);
        subject = row.subject;
        namesWhatWasStated = hasInfix "by a int" row.message;
        namesWhatExists = hasInfix "`flakelet`, `image`" row.message;
        # A table, not an evaluation error, and no realiser chosen for the entry
        # on the statement's behalf.
        table = map (r: r.id) reading.diagnostics;
        realiser = reading.manifest.entries.${oneKey}.realiser;
        refused = reading.refused;
      };
      expected = {
        ids = [ "operator-realiser-unknown" ];
        count = 1;
        subject = oneKey;
        namesWhatWasStated = true;
        namesWhatExists = true;
        table = [ "operator-realiser-unknown" ];
        realiser = 3;
        refused = true;
      };
    };

  testADeploymentWhoseDiagnosticsCarryAnError =
    let
      reading = reader.read {
        inherit (worked) plan diagnostics;
        realise = workedRealise;
      };
    in
    {
      expr = {
        applicable = worked.applicable;
        refused = reading.refused;
        ownRows = reading.rows;
        carriesTheTable = hasInfix "clients names three entries" reading.refusal;
        carriesTheReason = hasInfix "not applicable" reading.refusal;
        tableIsTheTable = reading.diagnostics == worked.diagnostics;
        # Applicability is read from the rows: the reading carries no field of
        # its own claiming it, and every entry is still named.
        everyEntryStillRead = placedOf worked.plan == sorted (attrNames reading.entries);
        applicabilityIsTheRows =
          reading.refused == (filter (r: r.severity == "error") reading.diagnostics != [ ]);
      };
      expected = {
        applicable = false;
        refused = true;
        ownRows = [ ];
        carriesTheTable = true;
        carriesTheReason = true;
        tableIsTheTable = true;
        everyEntryStillRead = true;
        applicabilityIsTheRows = true;
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
    in
    {
      expr = {
        keys = attrNames reading.manifest.entries;
        entry = builtins.removeAttrs entry [ "key" ];
        # The digest itself is `tests/unit/image.nix`'s subject. What the manifest
        # owes is that it publishes one.
        versioned = builtins.match "[0-9a-f]{16}" entry.key != null;
        units = reading.manifest.entries."nightly:client@alpha".units;
        withATimer = timers.manifest.entries.${oneKey}.units;
        unplacedContributeNothing = filter (key: builtins.match ".*:vars/.*" key != null) (
          attrNames reading.manifest.entries
        );
        everyPlacedKeyOnce = placedOf worked.plan == sorted (attrNames reading.manifest.entries);
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
          realiser = "image";
          profile = "trusted";
          machine = "vault";
          address = "vault.example";
          units = [ "vault-repo-server-borgRepo.service" ];
        };
        versioned = true;
        units = [ "nightly-client-borgPush.service" ];
        withATimer = [
          "svc-only-only.service"
          "svc-only-only.timer"
        ];
        unplacedContributeNothing = [ ];
        everyPlacedKeyOnce = true;
      };
    };

  testABuildStatesTheShapeOfItsRecordAndTheStoreItUsed =
    let
      empty = reader.read { plan = { }; };
      elsewhere = reader.read {
        plan = { };
        storeDir = "/elsewhere/store";
      };
    in
    {
      expr = {
        version = workedRead.manifest.version;
        storeDir = workedRead.manifest.storeDir;
        placingNothing = {
          entries = attrNames empty.manifest.entries;
          version = empty.manifest.version;
          storeDir = empty.manifest.storeDir;
        };
        stated = elsewhere.manifest.storeDir;
      };
      expected = {
        version = 3;
        storeDir = builtins.storeDir;
        placingNothing = {
          entries = [ ];
          version = 3;
          storeDir = builtins.storeDir;
        };
        stated = "/elsewhere/store";
      };
    };

  testTheRecordPublishesEachRealisersScopes =
    let
      empty = reader.read { plan = { }; };
    in
    {
      expr = {
        realisers = builtins.mapAttrs (_: r: { inherit (r) scopes; }) workedRead.manifest.realisers;
        # The lists the record carries are the realisers' own statements rather
        # than a table this reading keeps beside them.
        eachIsTheRealisersOwn = {
          image = workedRead.manifest.realisers.image.scopes == imageReader.scopes;
          flakelet = workedRead.manifest.realisers.flakelet.scopes == flakeletReader.scopes;
        };
        # A reading that places nothing publishes the table too: it is a fact of
        # the realisers the reading was handed and not of the entries.
        placingNothing = builtins.mapAttrs (_: r: { inherit (r) scopes; }) empty.manifest.realisers;
        everyRealiserTheReadingKnows = attrNames workedRead.manifest.realisers == reader.realisers;
      };
      expected = {
        realisers = {
          flakelet.scopes = [ "system" ];
          image.scopes = [
            "system"
            "user"
          ];
        };
        eachIsTheRealisersOwn = {
          image = true;
          flakelet = true;
        };
        placingNothing = {
          flakelet.scopes = [ "system" ];
          image.scopes = [
            "system"
            "user"
          ];
        };
        everyRealiserTheReadingKnows = true;
      };
    };

  # What a machine's own answer names a realiser's holdings by. The record is
  # the whole interface to a build, so a command that cannot evaluate a realiser
  # reads this out of the record rather than restating a rule whose one home is
  # the realiser.
  testTheRecordPublishesWhatAMachineNamesAFlakeletHoldingBy =
    let
      # Every entry of this deployment states the default realiser, which is the
      # endpoint one.
      p = realiser.planned { } simple;
      reading = reader.read { plan = p.plan; };
      published = reading.manifest.realisers.flakelet.holdings;
      prefix = published.urlPrefix;
      url = (flakeletReader.meta (flakeletReader.read { inherit (p) plan key; })).flake_url;
    in
    {
      expr = {
        inherit published;
        stated = map (e: e.realiser) (builtins.attrValues reading.manifest.entries);
        # Read off the realiser rather than restated by the reading, which is
        # what lets a third realiser be published by existing.
        theRealisersOwn = published == flakeletReader.holdings;
        # The published value is the one the realiser writes into the artifact
        # it builds: the url the endpoint answers with is that string and the
        # plan key, so a reader of the record alone reads the key back out.
        theArtifactsUrl = url;
        theUrlBeginsWithIt = builtins.substring 0 (builtins.stringLength prefix) url == prefix;
        whatFollowsIt = builtins.substring (builtins.stringLength prefix) (builtins.stringLength url) url;
        # It says how an answer is recognised and never which entries exist.
        namesNoEntry = filter (k: hasInfix k (toJSON published)) (attrNames reading.manifest.entries);
      };
      expected = {
        published = {
          urlPrefix = "plan:";
        };
        stated = [ "flakelet" ];
        theRealisersOwn = true;
        theArtifactsUrl = "plan:svc:only@one";
        theUrlBeginsWithIt = true;
        whatFollowsIt = "svc:only@one";
        namesNoEntry = [ ];
      };
    };

  # A machine may hold an entry of a realiser this build no longer states - the
  # entry that was dropped may have been the last one of its realiser - so the
  # table is a fact of the realisers the reading was handed and not of the
  # entries.
  testARecordPublishesTheFactForARealiserItsEntriesDoNotState =
    let
      reading = reader.read { plan = (realiser.planned { } simple).plan; };
    in
    {
      expr = {
        stated = planner.util.uniqueStrings (
          map (e: e.realiser) (builtins.attrValues reading.manifest.entries)
        );
        forTheStatedOne = reading.manifest.realisers.flakelet.holdings;
        forTheOneNoEntryStates = reading.manifest.realisers.image.holdings;
        forEveryRealiserTheReadingKnows = attrNames reading.manifest.realisers == reader.realisers;
        # And for a deployment that places nothing at all, which states no
        # realiser either.
        placingNothing =
          builtins.mapAttrs (_: r: r.holdings)
            (reader.read { plan = { }; }).manifest.realisers;
        # One table per realiser and not two: the holding sits in the record the
        # scopes are published in.
        besideTheScopes = reading.manifest.realisers;
      };
      expected = {
        stated = [ "flakelet" ];
        forTheStatedOne = {
          urlPrefix = "plan:";
        };
        forTheOneNoEntryStates = {
          separator = "_";
          digestAlphabet = "0123456789abcdef";
          digestLength = 16;
        };
        forEveryRealiserTheReadingKnows = true;
        placingNothing = {
          flakelet = {
            urlPrefix = "plan:";
          };
          image = {
            separator = "_";
            digestAlphabet = "0123456789abcdef";
            digestLength = 16;
          };
        };
        besideTheScopes = {
          flakelet = {
            holdings = {
              urlPrefix = "plan:";
            };
            scopes = [ "system" ];
          };
          image = {
            holdings = {
              separator = "_";
              digestAlphabet = "0123456789abcdef";
              digestLength = 16;
            };
            scopes = [
              "system"
              "user"
            ];
          };
        };
      };
    };

  # The crossing itself: the realiser records this suite is handed against the
  # table the reading published, so a realiser publishing none fails here rather
  # than reaching a deployment.
  testEveryRealiserTheReadingIsHandedPublishesTheFact =
    let
      handed = {
        flakelet = flakeletReader;
        image = imageReader;
      };
      publishes = endpoint: endpoint ? holdings && endpoint.holdings != { };
      published = workedRead.manifest.realisers;
    in
    {
      expr = {
        # The names crossed are the reading's own, so a third realiser the
        # reading grows fails this until it is handed here too.
        theNamesAreTheReadings = attrNames handed == reader.realisers;
        eachPublishes = builtins.mapAttrs (_: publishes) handed;
        asPublished = builtins.mapAttrs (
          name: endpoint: published.${name}.holdings == endpoint.holdings
        ) handed;
        # The same predicate over a realiser publishing none, which is what
        # fails the crossing.
        oneThatPublishesNone = publishes { nameRule = "anything"; };
        anEmptyRecordIsNoPublication = publishes { holdings = { }; };
      };
      expected = {
        theNamesAreTheReadings = true;
        eachPublishes = {
          flakelet = true;
          image = true;
        };
        asPublished = {
          flakelet = true;
          image = true;
        };
        oneThatPublishesNone = false;
        anEmptyRecordIsNoPublication = false;
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
              sealed = "/var/lib/planner/sealed/nightly/hostKey/ssh_host_ed25519_key.age";
              secrecy = "secret";
              owner = "root";
              group = "root";
              mode = "0400";
            };
            "ssh_host_ed25519_key.pub" = {
              path = "/run/vars/nightly/hostKey/ssh_host_ed25519_key.pub";
              sealed = "/var/lib/planner/sealed/nightly/hostKey/ssh_host_ed25519_key.pub.age";
              secrecy = "public";
              owner = "root";
              group = "root";
              mode = "0400";
            };
          };
        };
        gammaDelivery = [ "gamma" ];
        emptySet = {
          delivery = [ ];
          files."ca.pub" = {
            path = "/run/vars/holder/app/ca.pub";
            sealed = "/var/lib/planner/sealed/holder/app/ca.pub.age";
            secrecy = "public";
            owner = "root";
            group = "root";
            mode = "0400";
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
            owner = "root";
            group = "root";
            mode = "0400";
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
            sealed = "/var/lib/planner/sealed/holder/minted/token.age";
            secrecy = "secret";
            owner = "root";
            group = "root";
            mode = "0400";
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

  # The plan a planner produces no longer carries this key: a member named
  # `vars/x` is a `name-carries-key-separator` row, because a service entry
  # under it is a value entry's key. The record is moved onto that key by hand
  # here, because the claim is about the reading classifying a record by what it
  # records rather than by the text of its key.
  testAMemberIsNamedInsideTheValueNamespace =
    let
      result = planOf {
        instances.svc = {
          module = root { members.x.module = _: { impl = simple; }; };
          placement.every.x.machines = [ "one" ];
        };
      };
      plan = removeAttrs result.plan [ "svc:x@one" ] // {
        "svc:vars/x@one" = result.plan."svc:x@one";
      };
      # Both endpoints refuse `svc-vars/x` as a service name, so the reading
      # carries that row whichever realiser is stated. It is a row of its own and
      # not this scenario's, which is about the record a key is classified by.
      reading = reader.read {
        inherit plan;
        realise.default = {
          realiser = "image";
          profile = "trusted";
        };
      };
    in
    {
      expr = {
        planRows = map (r: r.id) result.diagnostics;
        entries = attrNames reading.entries;
        values = attrNames reading.values;
        service = reading.entries."svc:vars/x@one".service;
        rows = idsOf reading;
        read = (builtins.tryEval (builtins.deepSeq reading.manifest reading.manifest)).success;
      };
      expected = {
        planRows = [ ];
        entries = [ "svc:vars/x@one" ];
        values = [ ];
        service = "vars/x";
        rows = [ "operator-entry-name-refused" ];
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
        artifact = silent.manifest.entries.${oneKey} ? path;
        rows = idsOf silent;
        refused = silent.refused;
        askedRows = idsOf asked;
        askedRefused = asked.refused;
        namesTheEntry = hasInfix "`${oneKey}`" row.message;
      };
      expected = {
        recorded = [ oneKey ];
        machine = "one";
        artifact = false;
        rows = [ ];
        refused = false;
        askedRows = [ "operator-entry-realises-nothing" ];
        askedRefused = true;
        namesTheEntry = true;
      };
    };

  testAProfileIsInheritedFromTheDefaultStatement =
    let
      reading = readOf {
        default = {
          realiser = "image";
          profile = "strict";
        };
        "svc:only".realiser = "image";
      } one;
      entry = reading.manifest.entries.${oneKey};
    in
    {
      expr = {
        realiser = entry.realiser;
        profile = entry.profile;
        rows = idsOf reading;
        refused = reading.refused;
      };
      expected = {
        realiser = "image";
        profile = "strict";
        rows = [ ];
        refused = false;
      };
    };

  testAStatedProfileIsOutsideTheDomain =
    let
      reading = readOf {
        "svc:only" = {
          realiser = "image";
          profile = "stricT";
        };
      } one;
      row = builtins.head (rowsById "operator-image-profile-unknown" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesTheProfileStated = hasInfix "`stricT`" row.message;
        namesTheProfilesThatExist = hasInfix "`strict`" row.message && hasInfix "`trusted`" row.message;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-image-profile-unknown" ];
        subject = oneKey;
        namesTheProfileStated = true;
        namesTheProfilesThatExist = true;
        refused = true;
      };
    };

  # A profile of another kind is the same fact as a profile outside the domain,
  # so it earns the same row and indexes nothing the realiser holds: the digest
  # the manifest publishes forces beside it.
  testAStatementCarriesAProfileOfAnotherKind =
    let
      reading = readOf {
        default = {
          realiser = "image";
          profile = 3;
        };
      } one;
      row = builtins.head (rowsById "operator-image-profile-unknown" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesWhatWasStated = hasInfix "profile a int" row.message;
        namesTheProfilesThatExist = hasInfix "`strict`" row.message && hasInfix "`trusted`" row.message;
        # The value reaches no profile table, so nothing is denied on the
        # entry's behalf and the record the manifest publishes is answerable.
        denied = rowsById "operator-entry-access-denied" reading;
        digest = isString reading.manifest.entries.${oneKey}.key;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-image-profile-unknown" ];
        subject = oneKey;
        namesWhatWasStated = true;
        namesTheProfilesThatExist = true;
        denied = [ ];
        digest = true;
        refused = true;
      };
    };

  testAStatementNamesAnEntryThePlanDoesNotCarry =
    let
      reading = readOf {
        "svc:onlyy" = {
          realiser = "image";
          profile = "strict";
        };
      } one;
      row = builtins.head (rowsById "operator-statement-names-nothing" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesTheKeysThePlanCarries =
          hasInfix "`${oneKey}`" row.message && hasInfix "`svc:only`" row.message;
        realisedUnderTheDefaultInstead = reading.manifest.entries.${oneKey}.realiser;
        profile = reading.manifest.entries.${oneKey}.profile;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-statement-names-nothing" ];
        subject = "svc:onlyy";
        namesTheKeysThePlanCarries = true;
        realisedUnderTheDefaultInstead = "flakelet";
        profile = null;
        refused = true;
      };
    };

  testAStatementIsNotARecord =
    let
      reading = readOf { "svc:only" = "image"; } one;
      row = builtins.head (rowsById "operator-statement-not-a-record" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesTheStatement = hasInfix "`svc:only`" row.message;
        namesWhatWasFound = hasInfix "the string `image`" row.message;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-statement-not-a-record" ];
        subject = oneKey;
        namesTheStatement = true;
        namesWhatWasFound = true;
        refused = true;
      };
    };

  testAConfigurationFileMeetsARealiserWithNoAssembleStep =
    let
      reading = readOf { } refBearing;
      row = builtins.head (rowsById "operator-entry-path-not-assembled" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesThePath = hasInfix "`/etc/agent.conf`" row.message;
        namesTheReference = hasInfix "`/run/vars/svc/hostKey/key`" row.message;
        namesTheRealiser = hasInfix "`flakelet`" row.message;
        statesTheRealisersOwnRule = hasInfix flakeletReader.pathRule row.message;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-entry-path-not-assembled" ];
        subject = "svc:only@one";
        namesThePath = true;
        namesTheReference = true;
        namesTheRealiser = true;
        statesTheRealisersOwnRule = true;
        refused = true;
      };
    };

  # The other half of the same question: the bytes exist before activation and
  # the record does not, so the deployment is inapplicable and every entry of it
  # is still read. No artifact of it is built, which is what refusal means here.
  testAConfigurationFileMeetsARealiserThatInstallsNothing =
    let
      reading = readOf { } (deployment ownedConfigFile);
      row = builtins.head (rowsById "operator-entry-path-not-installable" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        severity = row.severity;
        namesThePath = hasInfix "`/etc/agent.conf`" row.message;
        namesTheRecordStated = hasInfix "postgres:postgres at mode 0440" row.message;
        namesTheStoresOwn = hasInfix "root:root at mode 0444" row.message;
        statesTheRealisersOwnRule = hasInfix flakeletReader.recordRule row.message;
        resolutionNamesBothWaysOut =
          hasInfix "root:root at mode 0444" row.resolution && hasInfix "`image`" row.resolution;
        everyEntryStillRead = attrNames reading.entries;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-entry-path-not-installable" ];
        subject = oneKey;
        severity = "error";
        namesThePath = true;
        namesTheRecordStated = true;
        namesTheStoresOwn = true;
        statesTheRealisersOwnRule = true;
        resolutionNamesBothWaysOut = true;
        everyEntryStillRead = [ oneKey ];
        refused = true;
      };
    };

  # A plan record is read for its kind too. The planner refuses a configuration
  # file that states no mode and records it with none, and the comparisons this
  # reading makes against that record interpolate it, so the absence is a row
  # here rather than a coercion.
  testAConfigurationFileRecordCarriesNoMode =
    let
      result = deployment modeless;
      reading = reader.read { inherit (result) plan diagnostics; };
      row = builtins.head (rowsById "operator-plan-field-malformed" reading);
    in
    {
      expr = {
        # The planner records the file with no mode rather than pruning it.
        recorded = result.plan.${oneKey}.configData."/etc/agent.conf".mode;
        rows = idsOf reading;
        subject = row.subject;
        namesTheField = hasInfix "`mode`" row.message;
        namesTheFile = hasInfix "`/etc/agent.conf`" row.message;
        namesWhatWasFound = hasInfix "as a null" row.message;
        severity = row.severity;
        # The table the deployment's other rows are in, and no decision about
        # the file: the path reaches neither of the two record comparisons.
        table = map (r: r.id) reading.diagnostics;
        entries = attrNames reading.manifest.entries;
        refused = reading.refused;
      };
      expected = {
        recorded = null;
        rows = [ "operator-plan-field-malformed" ];
        subject = oneKey;
        namesTheField = true;
        namesTheFile = true;
        namesWhatWasFound = true;
        severity = "error";
        table = [
          "config-file-mode-missing"
          "operator-plan-field-malformed"
        ];
        entries = [ oneKey ];
        refused = true;
      };
    };

  # Which fields reach a unit file is the realiser's own table, so a field the
  # library accepted and no table names is a row before any build raises.
  testAFieldNoBuilderRenders =
    let
      reading = readOf { } (deployment extendedBeyondTheTable);
      row = builtins.head (rowsById "operator-entry-extension-field-unrendered" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesTheUnit = hasInfix "unit `only`" row.message;
        namesTheField = hasInfix "`blockIODeviceWeight`" row.message;
        namesTheBackend = hasInfix "`systemd`" row.message;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-entry-extension-field-unrendered" ];
        subject = "svc:only@one";
        namesTheUnit = true;
        namesTheField = true;
        namesTheBackend = true;
        refused = true;
      };
    };

  testTheSameFieldUnderARealiserThatRendersIt =
    let
      reading = readOf {
        "svc:only" = {
          realiser = "image";
          profile = "trusted";
        };
      } (deployment extendedBeyondTheTable);
    in
    {
      expr = {
        rows = idsOf reading;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-entry-extension-field-unrendered" ];
        refused = true;
      };
    };

  # The field is taken from the realiser's own table rather than a list restated
  # here, so a table that gains a field is a field this row stops naming with no
  # edit under `operator/`.
  testAFieldAddedToARealisersTableStopsBeingReported =
    let
      rendered = builtins.head (sorted (attrNames imageReader.systemdDirectives));
      inTheTable = planner.unitExtension {
        backend = "systemd";
        name = "rendered";
        fields.${rendered}.type = support.korora.string;
      };
      reading = readOf { } (
        deployment (_: {
          closure = [ borgbackup ];
          units.only = {
            command = "${borgbackup}/bin/borg serve";
            extends = [
              {
                extension = inTheTable;
                values.${rendered} = "on";
              }
            ];
          };
        })
      );
    in
    {
      expr = {
        rows = idsOf reading;
        refused = reading.refused;
        artifact = reading.entries."svc:only@one".artifact;
      };
      expected = {
        rows = [ ];
        refused = false;
        artifact = "entries/svc-only-one";
      };
    };

  testAnEntryWithConfigurationDataIsRealisedAsAnImage =
    let
      reading = workedRead;
    in
    {
      expr = {
        rows = idsOf reading;
        refused = reading.refused;
        realiser = reading.manifest.entries."vault-repo:server@vault".realiser;
        artifact = reading.entries."vault-repo:server@vault".artifact;
      };
      expected = {
        rows = [ ];
        refused = false;
        realiser = "image";
        artifact = "entries/vault-repo-server-vault";
      };
    };

  testAnEntryIsStatedForARealiserItsMachineCannotRun =
    let
      result = planner.mkPlan {
        machines = support.machines // {
          laptop = support.laptop;
        };
        instances.svc = {
          module = soleRoot { module = _: { impl = simple; }; };
          placement.every.only.machines = [ "laptop" ];
        };
      };
      reading = readOf { } result;
      row = builtins.head (rowsById "operator-entry-service-manager-mismatch" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesWhatTheMachineRuns = hasInfix "`launchd`" row.message;
        namesWhatTheRealiserEmitsFor = hasInfix "`systemd`" row.message;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-entry-service-manager-mismatch" ];
        subject = "svc:only@laptop";
        namesWhatTheMachineRuns = true;
        namesWhatTheRealiserEmitsFor = true;
        refused = true;
      };
    };

  testAnEntryWhoseStatedRealiserExcludesItsMachinesScopeIsRefused =
    let
      reading = readOf { } onAnAccount.result;
      row = builtins.head (rowsById "operator-entry-scope-unsupported" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesTheEntry = hasInfix "`svc:only@account`" row.message;
        namesTheMachinesScope = hasInfix "in the `user` scope" row.message;
        namesThePublishedScopes = hasInfix "realises `system`" row.message;
        refused = reading.refused;
        # The image realiser publishes both scopes, so the same placement stated
        # for it is no row: what is crossed is the realiser's own statement and
        # never a rule of this reading.
        underTheImage = idsOf (underImage "trusted" onAnAccount.result);
      };
      expected = {
        rows = [ "operator-entry-scope-unsupported" ];
        subject = "svc:only@account";
        namesTheEntry = true;
        namesTheMachinesScope = true;
        namesThePublishedScopes = true;
        refused = true;
        underTheImage = [ ];
      };
    };

  testTheRealisersOwnRefusalCarriesTheRowsIdentifier =
    let
      reading = readOf { } onAnAccount.result;
      row = builtins.head (rowsById "operator-entry-scope-unsupported" reading);
      raised = forced flakeletReader.read { inherit (onAnAccount) plan key; };
    in
    {
      expr = {
        theRealiserRefusesToo = raised.success;
        # The pairing is the account the refusal carries, not the wording of
        # either sentence.
        theAccountNamesTheRow = flakeletReader.accounts.scopeUnsupported.id;
        theRowAboveIsTheSame = row.id;
        # The sentence the realiser prints is its own published rule, and the
        # row above states the scopes rather than restating that sentence.
        theRealiserStatesTheUpstreamFacts = map (needle: hasInfix needle flakeletReader.scopeRule) [
          "/run/systemd/system"
          "/var/lib/flakelet"
        ];
      };
      expected = {
        theRealiserRefusesToo = false;
        theAccountNamesTheRow = "operator-entry-scope-unsupported";
        theRowAboveIsTheSame = "operator-entry-scope-unsupported";
        theRealiserStatesTheUpstreamFacts = [
          true
          true
        ];
      };
    };

  testANameTheEndpointRefusesIsARowBeforeItIsARaise =
    let
      result = planOf {
        instances.svc = {
          module = root { members."needs.a.dot".module = _: { impl = simple; }; };
          placement.every."needs.a.dot".machines = [ "one" ];
        };
      };
      reading = readOf { } result;
      row = builtins.head (rowsById "operator-entry-name-refused" reading);
      raised = forced flakeletReader.read {
        inherit (result) plan;
        key = "svc:needs.a.dot@one";
      };
    in
    {
      expr = {
        rows = idsOf reading;
        subject = row.subject;
        namesTheName = hasInfix "`svc-needs.a.dot`" row.message;
        statesTheRealisersOwnRule = hasInfix flakeletReader.nameRule row.message;
        theRealiserRaisesToo = raised.success;
        refused = reading.refused;
      };
      expected = {
        rows = [ "operator-entry-name-refused" ];
        subject = "svc:needs.a.dot@one";
        namesTheName = true;
        statesTheRealisersOwnRule = true;
        theRealiserRaisesToo = false;
        refused = true;
      };
    };

  testAUnitNameOutsideTheRuleIsRefusedNamingTheEntry =
    let
      # `?` is a store name nix admits and a shell glob, so nothing below this
      # reading refuses it: the abort it earns names neither the entry nor the
      # declaration.
      result = planOf {
        instances."sv?c" = {
          module = soleRoot { module = _: { impl = simple; }; };
          placement.every.only.machines = [ "one" ];
        };
      };
      reading = underImage "trusted" result;
      row = builtins.head (rowsById "operator-entry-name-refused" reading);
      raised = forced imageReader.read {
        inherit (result) plan;
        key = "sv?c:only@one";
        profile = "trusted";
      };
    in
    {
      expr = {
        thePlannerAllowsIt = map (r: r.id) result.diagnostics;
        rows = idsOf reading;
        subject = row.subject;
        namesTheName = hasInfix "`sv?c-only`" row.message;
        statesTheRealisersOwnRule = hasInfix imageReader.nameRule row.message;
        theRealiserRaisesToo = raised.success;
        # The reading refuses, so `operator/default.nix` builds the two tables
        # and the artifact of no entry, while the entry itself is still read.
        refused = reading.refused;
        theEntryIsStillRead = reading.entries."sv?c:only@one".realised;
      };
      expected = {
        thePlannerAllowsIt = [ ];
        rows = [ "operator-entry-name-refused" ];
        subject = "sv?c:only@one";
        namesTheName = true;
        statesTheRealisersOwnRule = true;
        theRealiserRaisesToo = false;
        refused = true;
        theEntryIsStillRead = true;
      };
    };

  testTheNameRefusalIsPrecededByItsRow =
    let
      result = planOf {
        instances."sv?c" = {
          module = soleRoot { module = _: { impl = simple; }; };
          placement.every.only.machines = [ "one" ];
        };
      };
      reading = underImage "trusted" result;
      row = builtins.head (rowsById "operator-entry-name-refused" reading);
    in
    {
      expr = {
        # The account each refusal carries names the row a producing layer
        # builds, which is what `tests/unit/diagnostics.nix` crosses wholesale.
        theServiceNameRefusalNamesARow = imageReader.accounts.nameRefused.id;
        theUnitFileRefusalNamesTheSameRow = imageReader.accounts.unitRefused.id;
        theRowIsProduced = row.id;
        # One rule, asked of the realiser rather than restated: the row's own
        # sentence is the realiser's string and not a copy of it.
        theRowStatesTheRealisersRule = hasInfix imageReader.nameRule row.message;
        andItIsNotFlakelets = imageReader.nameRule == flakeletReader.nameRule;
      };
      expected = {
        theServiceNameRefusalNamesARow = "operator-entry-name-refused";
        theUnitFileRefusalNamesTheSameRow = "operator-entry-name-refused";
        theRowIsProduced = "operator-entry-name-refused";
        theRowStatesTheRealisersRule = true;
        andItIsNotFlakelets = false;
      };
    };

  # The two realisers render one unit set under two rules, and this file is where
  # they differ: `@` is the service manager's instance marker and no character of
  # a store name.
  testAUnitFileIsHeldToTheStatedRealisersRule =
    let
      result = deployment (_: {
        closure = [ borgbackup ];
        units."web@one".command = "${borgbackup}/bin/borg serve";
      });
      asAnImage = underImage "trusted" result;
      row = builtins.head (rowsById "operator-entry-name-refused" asAnImage);
      raised = forced imageReader.read {
        inherit (result) plan;
        key = oneKey;
        profile = "trusted";
      };
      read = forced flakeletReader.read {
        inherit (result) plan;
        key = oneKey;
      };
    in
    {
      expr = {
        thePlannerAllowsIt = map (r: r.id) result.diagnostics;
        rows = idsOf asAnImage;
        subject = row.subject;
        namesTheFile = hasInfix "`svc-only-web@one.service`" row.message;
        statesTheImagesRule = hasInfix (imageReader.unitRule "svc-only") row.message;
        theImageRaisesToo = raised.success;
        # The same entry under the default realiser, whose rule reads the `@` as
        # an instance marker: no row and no refusal, the image's rule reaching it
        # nowhere.
        underTheDefault = idsOf (readOf { } result);
        theEndpointReadsIt = read.success;
      };
      expected = {
        thePlannerAllowsIt = [ ];
        rows = [ "operator-entry-name-refused" ];
        subject = oneKey;
        namesTheFile = true;
        statesTheImagesRule = true;
        theImageRaisesToo = false;
        underTheDefault = [ ];
        theEndpointReadsIt = true;
      };
    };

  testAUnitNeedingAHostUserMeetsAConfiningProfile =
    let
      result = deployment (_: {
        closure = [ borgbackup ];
        units.only = {
          command = "${borgbackup}/bin/borg serve";
          user = "borg";
        };
      });
      confined = underImage "strict" result;
      allowed = underImage "trusted" result;
      row = builtins.head (rowsById "operator-entry-access-denied" confined);
    in
    {
      expr = {
        rows = idsOf confined;
        subject = row.subject;
        namesTheUnit = hasInfix "`only`" row.message;
        namesTheAccess = hasInfix "a static host user" row.message;
        namesTheProfile = hasInfix "`strict`" row.message;
        saysItIsNotWidened = hasInfix "not widened on the entry" row.evidence;
        underATrustedProfile = idsOf allowed;
      };
      expected = {
        rows = [ "operator-entry-access-denied" ];
        subject = oneKey;
        namesTheUnit = true;
        namesTheAccess = true;
        namesTheProfile = true;
        saysItIsNotWidened = true;
        underATrustedProfile = [ ];
      };
    };

  testAnEntryOwningARootOnlyFileMeetsAConfiningProfile =
    let
      confined = reader.read {
        inherit (worked) plan;
        realise = workedRealise // {
          "nightly:client" = {
            realiser = "image";
            profile = "strict";
          };
        };
      };
      rows = rowsById "operator-entry-access-denied" confined;
      row = builtins.head rows;
    in
    {
      expr = {
        rows = sorted (planner.util.uniqueStrings (map (r: r.id) confined.rows));
        subjects = sorted (planner.util.uniqueStrings (map (r: r.subject) rows));
        namesTheAccess = hasInfix "a host file only root may read" row.message;
        namesTheProfile = hasInfix "`strict`" row.message;
        refused = confined.refused;
      };
      expected = {
        rows = [ "operator-entry-access-denied" ];
        subjects = [
          "nightly:client@alpha"
          "nightly:client@beta"
          "nightly:client@gamma"
        ];
        namesTheAccess = true;
        namesTheProfile = true;
        refused = true;
      };
    };

  testAMachineOfAPlacedEntryDeclaresNoAddress =
    let
      bare = reader.read { plan = addressless; };
    in
    {
      expr = {
        ids = idsOf bare;
        recordsTheAbsence = bare.manifest.entries."svc:only@bare" ? address;
        address = bare.manifest.entries."svc:only@bare".address;
        artifact = bare.manifest.entries."svc:only@bare".path;
        refused = bare.refused;
      };
      expected = {
        ids = [ ];
        recordsTheAbsence = true;
        address = null;
        artifact = "entries/svc-only-bare";
        refused = false;
      };
    };

  testABuildOfADeploymentTheRegistryMadeInapplicable =
    let
      result = planOf {
        machines.bare = {
          tags = [ ];
          system = "x86_64-linux";
          serviceManager = "systemd";
        };
        instances.svc = {
          module = soleRoot { module = _: { impl = simple; }; };
          placement.every.only.machines = [ "bare" ];
        };
      };
      reading = reader.read { inherit (result) plan diagnostics; };
    in
    {
      expr = {
        applicable = result.applicable;
        refused = reading.refused;
        ownRows = idsOf reading;
        # plan.json, diagnostics.json and diagnostics.txt are the three files the
        # farm carries whatever the reading answers; an entry artifact is linked
        # only for an entry the reading names, and there is none.
        thePlanIsPublished = attrNames result.plan;
        theTableIsPublished = map (r: r.id) reading.diagnostics;
        noEntryArtifact = attrNames reading.manifest.entries;
        namesTheMachine = hasInfix "`bare`" reading.refusal;
        namesTheRegistryFile = hasInfix "deployment/machines.nix" reading.refusal;
      };
      expected = {
        applicable = false;
        refused = true;
        ownRows = [ ];
        thePlanIsPublished = [
          "machine:bare"
          "svc:only"
        ];
        theTableIsPublished = [ "machine-target-incomplete" ];
        noEntryArtifact = [ ];
        namesTheMachine = true;
        namesTheRegistryFile = true;
      };
    };

  testAMachineAddressChangesAndNoArtifactByteDoes =
    let
      deploymentAt =
        address:
        planner.mkPlan {
          machines.one = {
            inherit address;
            tags = [ ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
          instances.svc = {
            module = soleRoot { module = _: { impl = simple; }; };
            placement.every.only.machines = [ "one" ];
          };
        };
      before = deploymentAt "one.example:22";
      after = deploymentAt "moved.example:22";
      identityOf = result: (readOf { } result).manifest.entries.${oneKey}.key;
      artifactOf = result: (readOf { } result).manifest.entries.${oneKey}.path;
    in
    {
      expr = {
        planKeyMoves = before.plan.${oneKey}.key != after.plan.${oneKey}.key;
        machineKeyMoves = before.plan."machine:one".key != after.plan."machine:one".key;
        publishedIdentityStays = identityOf before == identityOf after;
        artifactNameStays = artifactOf before == artifactOf after;
      };
      expected = {
        planKeyMoves = true;
        machineKeyMoves = true;
        publishedIdentityStays = true;
        artifactNameStays = true;
      };
    };

  testARootOnlyValueUnderAConfiningProfile =
    let
      result = support.valuePlan { openIt = true; };
      confined = underImage "strict" result;
      row = builtins.head (rowsById "operator-entry-access-denied" confined);
    in
    {
      expr = {
        rows = idsOf confined;
        namesTheUnit = hasInfix "`only`" row.message;
        namesTheFile = hasInfix "`/run/vars/svc/hostKey/key`" row.message;
        namesTheRecord = hasInfix "`root:root at mode 0400`" row.message;
        namesTheAccount = hasInfix "`a transient account`" row.message;
        # The same condition ends the build: the row is above the raise, which is
        # what `tests/unit/diagnostics.nix` crosses account against row for.
        theRealiserRefuses =
          !(builtins.tryEval (
            builtins.deepSeq (imageReader.read {
              plan = result.plan;
              key = "svc:only@one";
              profile = "strict";
            }) null
          )).success;
      };
      expected = {
        rows = [ "operator-entry-access-denied" ];
        namesTheUnit = true;
        namesTheFile = true;
        namesTheRecord = true;
        namesTheAccount = true;
        theRealiserRefuses = true;
      };
    };

  # The reading computes the values an entry is shown once and hands them to
  # every entry point, so a consumer of a value another entry generated is shown
  # that value's path by the same reading that shows an owner its own.
  testTheReadingShowsAConsumerAPeersValue =
    let
      result = support.peerValuePlan { };
      reading = underImage "trusted" result;
      shownTo =
        key:
        map (p: p.path) (
          imageReader.hostPaths {
            inherit key;
            entry = result.plan.${key};
            generated =
              (imageReader.valuesOf {
                index = imageReader.valueIndex result.plan;
                inherit key;
                entry = result.plan.${key};
              }).generated;
          }
        );
    in
    {
      expr = {
        rows = idsOf reading;
        consumer = shownTo "app:only@one";
        owner = shownTo "holder:only@one";
        # The digest the reading publishes is the one the entry point answers for
        # the same list, which is what a report compares a machine against.
        digestIsPublished =
          reading.manifest.entries."app:only@one".key == reading.entries."app:only@one".digest;
        andTheBuildIsApplicable = reading.refused;
      };
      expected = {
        rows = [ ];
        consumer = [ support.peerValuePath ];
        owner = [ support.peerValuePath ];
        digestIsPublished = true;
        andTheBuildIsApplicable = false;
      };
    };

  # A read naming a value path the plan's own value records deliver to another
  # machine is a plan whose records disagree: the delivery set is derived from
  # the reads that name a value, so the row is this reading's and not `mkPlan`'s.
  testAReadNamingAValueThePlanDoesNotDeliverThere =
    let
      result = support.peerValuePlan { };
      value = result.plan."holder:vars/token@one";
      elsewhere = result.plan // {
        "holder:vars/token@one" = value // {
          delivery = [ "two" ];
        };
      };
      reading = reader.read {
        plan = elsewhere;
        realise.default = {
          realiser = "image";
          profile = "trusted";
        };
      };
      row = builtins.head (rowsById "operator-entry-value-unaccounted" reading);
    in
    {
      expr = {
        subjects = map (r: r.subject) (rowsById "operator-entry-value-unaccounted" reading);
        namesTheSlot = hasInfix "`cred`" row.message;
        namesThePath = hasInfix "`${support.peerValuePath}`" row.message;
        namesTheMachine = hasInfix "`one`" row.message;
        saysWhyTheRecordsDisagree = hasInfix "derived from the reads that name it" row.evidence;
        refused = reading.refused;
        # No artifact of that entry is built: the realiser refuses the same
        # condition, which is what the account above it carries.
        theRealiserRefuses =
          !(forced imageReader.read {
            plan = elsewhere;
            key = "app:only@one";
            profile = "trusted";
          }).success;
      };
      expected = {
        subjects = [ "app:only@one" ];
        namesTheSlot = true;
        namesThePath = true;
        namesTheMachine = true;
        saysWhyTheRecordsDisagree = true;
        refused = true;
        theRealiserRefuses = true;
      };
    };

  testAReadNamingAPathNoValueRecordCarries =
    let
      result = support.peerValuePlan { };
      without = builtins.removeAttrs result.plan [ "holder:vars/token@one" ];
      reading = reader.read {
        plan = without;
        realise.default = {
          realiser = "image";
          profile = "trusted";
        };
      };
      refusal = forced imageReader.read {
        plan = without;
        key = "app:only@one";
        profile = "trusted";
      };
    in
    {
      expr = {
        ids = idsOf reading;
        subjects = map (r: r.subject) (rowsById "operator-entry-value-unaccounted" reading);
        # A refusal and never a missing attribute: the index is total, so a path
        # no value record carries is a sentence rather than an evaluation error.
        refuses = !refusal.success;
      };
      expected = {
        ids = [ "operator-entry-value-unaccounted" ];
        subjects = [ "app:only@one" ];
        refuses = true;
      };
    };

  # One entry claiming one name twice. The existing collision row's sentence is
  # about two entries, so the same-entry case earns a sentence of its own, and
  # the two-entry case is still the per-machine index's.
  testADeclaredUnitSpellingTheDerivedProbeFile =
    let
      taken = readOf { } (deployment (probedUnit "health"));
      renamedUnit = readOf { } (deployment (probedUnit "serve"));
      unprobed = readOf { } (deployment (unitNamed "health"));
      row = builtins.head (rowsById "operator-entry-probe-unit-file-taken" taken);
      colliding = readOf { } sharingAProbeFile;
      collision = builtins.head (rowsById "operator-entry-unit-file-collision" colliding);
    in
    {
      expr = {
        ids = idsOf taken;
        subject = row.subject;
        severity = row.severity;
        names = map (needle: hasInfix needle row.message) [
          "svc:only@one"
          "`health`"
          "`svc-only-health.service`"
        ];
        resolutionNamesBothWaysOut = map (needle: hasInfix needle row.resolution) [
          "rename unit `health`"
          "move the probe off"
        ];
        # Renaming either the unit or the probe removes the row, and the file the
        # entry derives is still published among its units.
        renamingTheUnit = rowsById "operator-entry-probe-unit-file-taken" renamedUnit;
        movingTheProbe = rowsById "operator-entry-probe-unit-file-taken" unprobed;
        unitsOfTheRenamedEntry = renamedUnit.manifest.entries."svc:only@one".units;
        unitsOfTheUnprobedEntry = unprobed.manifest.entries."svc:only@one".units;
        # Two entries on one machine deriving one probe file is the existing
        # per-machine namespace row, with no edit to that check.
        twoEntriesDerivingOne = rowsById "operator-entry-probe-unit-file-taken" colliding;
        theNamespaceRow = collision.subject;
        theNamespaceRowNamesTheFile = hasInfix "`a-b-c-health.service`" collision.message;
        theNamespaceRowNamesBoth = hasInfix "`a-b:c@one`, `a:b-c@one`" collision.message;
      };
      expected = {
        ids = [ "operator-entry-probe-unit-file-taken" ];
        subject = "svc:only@one";
        severity = "error";
        names = [
          true
          true
          true
        ];
        resolutionNamesBothWaysOut = [
          true
          true
        ];
        renamingTheUnit = [ ];
        movingTheProbe = [ ];
        unitsOfTheRenamedEntry = [
          "svc-only-health.service"
          "svc-only-serve.service"
        ];
        unitsOfTheUnprobedEntry = [ "svc-only-health.service" ];
        twoEntriesDerivingOne = [ ];
        theNamespaceRow = "a-b:c@one";
        theNamespaceRowNamesTheFile = true;
        theNamespaceRowNamesBoth = true;
      };
    };

  testAMachineThatReceivesAValueHasAnUnsealer =
    let
      record = delivered.machines.alpha;
    in
    {
      expr = {
        machines = attrNames delivered.machines;
        sealed = record.sealed;
        # Addressed by the machine's own name, with no projection: a name
        # carrying a key separator is refused before any key exists and machine
        # names are unique by construction.
        artifact = record.artifact;
        published = delivered.manifest.machines.alpha;
        # The unit the artifact carries, whose name the entries' own namespace
        # cannot reach.
        unit = record.unit;
        # The file records the restore is a function of: the runtime path, the
        # sealed path derived from it, and the ownership and mode the record
        # states for the plaintext.
        files = record.files;
        # The reading stays total and says nothing of its own about a machine
        # that seals nothing: the planner's own warning is the row.
        rows = delivered.rows;
      };
      expected = {
        machines = [
          "alpha"
          "beta"
          "delta"
        ];
        sealed = true;
        artifact = "machines/alpha";
        published = {
          sealed = true;
          scope = "system";
          path = "machines/alpha";
        };
        unit = "planner-unseal.service";
        files = [
          {
            path = "/run/vars/issuer/session/token";
            sealed = "/var/lib/planner/sealed/issuer/session/token.age";
            secrecy = "secret";
            owner = "nobody";
            group = "nogroup";
            mode = "0440";
          }
        ];
        rows = [ ];
      };
    };

  testAMachineThatReceivesNoValueHasNone = {
    expr = {
      # `gamma` runs an entry, declares a recipient, and is in no delivery
      # set: it is the delivery set and never the placement that decides who
      # holds a value.
      runsAnEntry = delivered.manifest.entries."issuer:api@gamma".machine;
      declaresARecipient =
        (deliveredPlan {
          seal = recipient;
          mode = "0400";
        })."machine:gamma".sealRecipient == recipient;
      read = delivered.machines ? gamma;
      published = delivered.manifest.machines ? gamma;
    };
    expected = {
      runsAnEntry = "gamma";
      declaresARecipient = true;
      read = false;
      published = false;
    };
  };

  testTwoBuildsOfOneDeploymentProduceOneUnsealer =
    let
      # The reading rather than a derivation: this suite evaluates without
      # `pkgs`, and the artifact is a function of exactly this record.
      again = reader.read {
        plan = deliveredPlan {
          seal = recipient;
          mode = "0400";
        };
      };
      rotatedRead = reader.read {
        plan = deliveredPlan {
          seal = rotated;
          mode = "0400";
        };
      };
      movedValue = reader.read {
        plan = deliveredPlan {
          seal = recipient;
          mode = "0440";
        };
      };
    in
    {
      expr = {
        twoReadings = again.machines == delivered.machines;
        # A rotation changes no field of any record, so it rebuilds nothing.
        aRotation = rotatedRead.machines == delivered.machines;
        rotationIsVisibleInThePlanAlone =
          (deliveredPlan {
            seal = rotated;
            mode = "0400";
          })."machine:alpha".sealRecipient;
        # Changing the values delivered to `delta` leaves the others' records
        # equal and moves `delta`'s own.
        oneMachinesValues = {
          alpha = movedValue.machines.alpha == delivered.machines.alpha;
          beta = movedValue.machines.beta == delivered.machines.beta;
          delta = movedValue.machines.delta == delivered.machines.delta;
        };
      };
      expected = {
        twoReadings = true;
        aRotation = true;
        rotationIsVisibleInThePlanAlone = rotated;
        oneMachinesValues = {
          alpha = true;
          beta = true;
          delta = false;
        };
      };
    };

  testAUserScopeMachineReceivesAUserUnit =
    let
      reading = reader.read { plan = onAccountPlan; };
    in
    {
      expr = {
        # The scope is what decides the manager, the wanting target and the
        # account, and it is the only thing about the machine the artifact is a
        # function of beside its value file records.
        scope = reading.machines.account.scope;
        published = reading.manifest.machines.account;
        # A machine that records none is system scope, which is the other answer
        # the same field gives.
        systemScope = delivered.machines.alpha.scope;
        rows = reading.rows;
      };
      expected = {
        scope = "user";
        published = {
          sealed = true;
          scope = "user";
          path = "machines/account";
        };
        systemScope = "system";
        rows = [ ];
      };
    };

  testTheUnitIsOrderedBeforeAnEntryThatReadsAValue =
    let
      # Stated as images, which is the realiser that runs a step on the machine:
      # the owner's own configuration file reads a delivered path, and the
      # refusal a step-less realiser makes about that is another test's.
      reading = reader.read {
        plan = orderedPlan;
        realise.default = {
          realiser = "image";
          profile = "trusted";
        };
      };
    in
    {
      expr = {
        # One rule covers both ways an entry's record can name a value's path:
        # a declared read landing the provider's path in the consumer's own unit,
        # and an entry's own configuration file naming it. An entry that names
        # none is not in the list.
        before = reading.machines.alpha.before;
        everyUnitOnTheMachine = sorted (
          builtins.concatLists (
            map (key: reading.manifest.entries.${key}.units) (attrNames reading.manifest.entries)
          )
        );
        rows = reading.rows;
      };
      expected = {
        before = [
          "watch-owner-load.service"
          "watch-reader-fetch.service"
        ];
        everyUnitOnTheMachine = [
          "watch-idle-tick.service"
          "watch-owner-load.service"
          "watch-reader-fetch.service"
        ];
        rows = [ ];
      };
    };

  testNoEntryCanDeriveTheUnsealingUnitsFileName =
    let
      # Every shape of the derivation, including the two components that spell
      # the machine unit's own words and one that carries a hyphen of its own.
      parts = [
        {
          instance = "i";
          service = "s";
          unit = "u";
        }
        {
          instance = "planner";
          service = "unseal";
          unit = "x";
        }
        {
          instance = "planner";
          service = "u";
          unit = "nseal";
        }
        {
          instance = "pl-anner";
          service = "unseal";
          unit = "x";
        }
      ];

      derivable = builtins.concatLists (
        map (
          p:
          imageReader.unitFilesOf (imageReader.nameOf { inherit (p) instance service; }) {
            ${p.unit} = {
              command = "/bin/true";
              probe = "/bin/true";
            };
          }
        ) parts
      );

      machineUnit = delivered.machines.alpha.unit;
    in
    {
      expr = {
        # `<instance>-<service>-<unit>` and the probe file derived from the same
        # two words each carry two hyphens outside their components, and the
        # machine-scoped unit carries one, so the two namespaces are disjoint by
        # construction rather than by a row.
        derivable = sorted derivable;
        everyDerivableNamesTwoOrMore = all (name: hyphens name >= 2) derivable;
        theMachineUnitNamesOne = hyphens machineUnit;
        noDerivableNameEqualsIt = filter (name: name == machineUnit) derivable;
      };
      expected = {
        derivable = [
          "i-s-health.service"
          "i-s-u.service"
          "pl-anner-unseal-health.service"
          "pl-anner-unseal-x.service"
          "planner-u-health.service"
          "planner-u-nseal.service"
          "planner-unseal-health.service"
          "planner-unseal-x.service"
        ];
        everyDerivableNamesTwoOrMore = true;
        theMachineUnitNamesOne = 1;
        noDerivableNameEqualsIt = [ ];
      };
    };

  testTheRecordNamesTheMachinesAValueReaches = {
    expr = {
      # Two of the three machines a value could have reached, and each record
      # says whether that machine's values are sealed.
      machines = attrNames delivered.manifest.machines;
      sealing = delivered.manifest.machines.alpha;
      # A machine in a delivery set that declares no recipient is in the table
      # and carries no path at all, the way an entry realised into nothing
      # does: an absent key is the absence it means, and a null is a value the
      # reading side would have to refuse.
      unsealed = delivered.manifest.machines.beta;
      noPath = delivered.manifest.machines.beta ? path;
      # The recipient is restated nowhere in the record: the plan's own
      # machine record carries it, and a second copy is a second answer.
      recordCarriesNoRecipient = hasInfix "age1" (toJSON delivered.manifest);
      planCarriesIt =
        (deliveredPlan {
          seal = recipient;
          mode = "0400";
        })."machine:alpha".sealRecipient;
    };
    expected = {
      machines = [
        "alpha"
        "beta"
        "delta"
      ];
      sealing = {
        sealed = true;
        scope = "system";
        path = "machines/alpha";
      };
      unsealed = {
        sealed = false;
        scope = "system";
      };
      noPath = false;
      recordCarriesNoRecipient = false;
      planCarriesIt = recipient;
    };
  };

  testADeploymentThatDeliversNothingCarriesTheTableAnyway =
    let
      empty = reader.read { plan = { }; };
      # A value entry whose delivery set is empty reaches no machine, so the
      # table is empty for the same reason and not for a different one.
      undelivered = reader.read { plan = unreceived; };
    in
    {
      expr = {
        carriesIt = empty.manifest ? machines;
        table = empty.manifest.machines;
        reading = empty.machines;
        emptyDeliverySet = {
          carriesIt = undelivered.manifest ? machines;
          table = undelivered.manifest.machines;
        };
      };
      expected = {
        carriesIt = true;
        table = { };
        reading = { };
        emptyDeliverySet = {
          carriesIt = true;
          table = { };
        };
      };
    };
}
