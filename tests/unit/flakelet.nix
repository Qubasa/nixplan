# The flakelet realiser's reading of a plan entry: the files it implies, the
# enablement it renders, the identity it stamps and the names it refuses.
#
# One test per scenario of specs/realiser/flakelet-artifact/spec.md that a pure
# evaluation can observe, which is every scenario about the artifact itself: the
# reading is what decides the files, the sections, the digest and the refusals,
# and a build only writes them down. What a real endpoint does with the artifact
# once it is on a machine is the machine layer's, in
# tests/e2e/wired-pair/test_wired_pair.py.
{
  planner,
  support,
  flakeletSource,
  imageSource,
}:
let
  inherit (builtins)
    attrNames
    concatLists
    filter
    tryEval
    ;

  inherit (support) planOf soleRoot;
  inherit (support.worked) borgbackup;

  # Both readers by store path: the suite runs from a generated entry point
  # whose sources are two unrelated store paths, so the shared reading is handed
  # over rather than found beside this one.
  reader = import (flakeletSource + "/read.nix") {
    inherit planner;
    reader = import (imageSource + "/read.nix") { inherit planner; };
  };

  planned =
    {
      instance ? "svc",
      machine ? "one",
    }:
    implementation: {
      key = "${instance}:only@${machine}";
      plan =
        (planOf {
          instances.${instance} = {
            module = soleRoot {
              module = _: {
                impl = implementation;
              };
            };
            placement.every.only.machines = [ machine ];
          };
        }).plan;
    };

  readOf =
    args: implementation:
    let
      p = planned args implementation;
    in
    reader.read { inherit (p) plan key; };

  # A refusal raises: this realiser produces bytes, and a name the endpoint
  # would reject is a deployment's mistake rather than something to normalise.
  # `deepSeq` because a refusal guards fields a lazy read would leave unforced.
  raises = value: !(tryEval (builtins.deepSeq value value)).success;

  simple = _: {
    closure = [ borgbackup ];
    units.web.command = "${borgbackup}/bin/borg serve";
  };

  withSchedule = _: {
    closure = [ borgbackup ];
    units = {
      web.command = "${borgbackup}/bin/borg serve";
      sweep = {
        command = "${borgbackup}/bin/borg prune";
        schedule = "daily";
        oneShot = true;
      };
    };
  };

  # The same entry with one unit field changed. The digest the endpoint compares
  # is a function of what the artifact is made of, so this is the difference a
  # rebuild would show, without a build.
  changedField = _: {
    closure = [ borgbackup ];
    units.web.command = "${borgbackup}/bin/borg serve --umask 077";
  };

  # An entry shown a host file. This realiser runs no step on the machine, so
  # each of the two kinds is refused rather than rendered into a unit naming a
  # path nothing creates.
  shownAConfigurationFile = _: {
    closure = [ borgbackup ];
    units.web.command = "${borgbackup}/bin/borg serve";
    configData."/etc/thing.conf" = {
      mode = "0444";
      reload = [ "web" ];
      render = [ { text = "value\n"; } ];
    };
  };

  # A generated file reaches a unit as a reference to a path on the machine,
  # which is the second kind of host path and the second refusal.
  shownAGeneratedFile = planOf {
    instances.svc = {
      module = soleRoot {
        module = _: {
          vars.hostKey.files."key".secrecy = "secret";
          impl =
            { vars, ... }:
            {
              closure = [ borgbackup ];
              units.web = {
                command = "${borgbackup}/bin/borg serve";
                env.KEYFILE = vars.hostKey."key".path;
              };
            };
        };
      };
      placement.every.only.machines = [ "one" ];
    };
    varsState.one.hostKey."key" = {
      present = true;
      content = "PRIVATE-KEY-BYTES";
    };
  };

  suffixOf =
    file:
    let
      m = builtins.match ".*(\\.[a-z]+)" file;
    in
    if m == null then "" else builtins.head m;

  filesOf =
    image:
    concatLists (
      map (
        unitName:
        let
          u = image.units.${unitName};
        in
        [ u.file ] ++ (if u.timer == null then [ ] else [ u.timer ])
      ) (attrNames image.units)
    );

  lastSection =
    text:
    let
      lines = filter (l: builtins.isString l && l != "") (builtins.split "\n" text);
    in
    filter (l: builtins.match "\\[[A-Za-z]+]" l != null) lines;
in
{
  # One entry, one artifact: the files it implies are the unit file of every
  # recorded unit, and the timer of every scheduled one.
  testOneEntryBecomesOneArtifact =
    let
      image = readOf { } simple;
    in
    {
      expr = {
        files = filesOf image;
        inherit (image) name;
      };
      expected = {
        files = [ "svc-only-web.service" ];
        name = "svc-only";
      };
    };

  # A schedule is a trigger: the service file and the timer file are two files
  # of one unit, and an entry without a schedule implies no timer at all.
  testAScheduledUnitBringsItsTrigger =
    let
      scheduled = readOf { } withSchedule;
      plain = readOf { } simple;
    in
    {
      expr = {
        scheduled = support.planner.util.sortStrings (filesOf scheduled);
        plain = filesOf plain;
      };
      expected = {
        scheduled = [
          "svc-only-sweep.service"
          "svc-only-sweep.timer"
          "svc-only-web.service"
        ];
        plain = [ "svc-only-web.service" ];
      };
    };

  # A long-running unit carries the section that makes the endpoint start it,
  # and it is the last section of the file: everything above it is what the
  # entry recorded.
  testALongRunningUnitIsWanted =
    let
      image = readOf { } simple;
      text = reader.renderUnit image "web";
    in
    {
      expr = {
        sections = lastSection text;
        install = support.hasInfix "\n[Install]\nWantedBy=multi-user.target\n" text;
        shared = support.hasInfix (reader.reader.renderUnit image "web") text;
        endsWithNewline = support.hasInfix "WantedBy=multi-user.target\n" text;
      };
      expected = {
        sections = [
          "[Unit]"
          "[Service]"
          "[Install]"
        ];
        install = true;
        shared = true;
        endsWithNewline = true;
      };
    };

  # The timer is enabled and the service is not: an `[Install]` on the service
  # of a scheduled unit would run the job at deploy time.
  testAScheduledUnitIsNotFiredByDeployingIt =
    let
      image = readOf { } withSchedule;
      service = reader.renderUnit image "sweep";
      timer = reader.renderTimer image "sweep";
    in
    {
      expr = {
        serviceSections = lastSection service;
        serviceHasInstall = support.hasInfix "[Install]" service;
        timerSections = lastSection timer;
        timerWantedBy = support.hasInfix "\n[Install]\nWantedBy=timers.target\n" timer;
        timerNamesItsService = support.hasInfix "Unit=svc-only-sweep.service" timer;
      };
      expected = {
        serviceSections = [
          "[Unit]"
          "[Service]"
        ];
        serviceHasInstall = false;
        timerSections = [
          "[Unit]"
          "[Timer]"
          "[Install]"
        ];
        timerWantedBy = true;
        timerNamesItsService = true;
      };
    };

  # The metadata is the plan's identity in the fields the endpoint reads back:
  # the key as the reference, the entry's version digest as the hash it
  # compares. The digest is the reading's, not the key.
  testTheArtifactCarriesThePlansIdentity =
    let
      image = readOf { } simple;
      meta = reader.meta image;
    in
    {
      expr = meta // {
        settingsHashIsTheVersion = meta.settings_hash == image.version;
        settingsHashIsNotTheKey = meta.settings_hash != image.key;
        settingsHashLength = builtins.stringLength meta.settings_hash;
      };
      expected = {
        version = 1;
        name = "svc-only";
        flake_url = "plan:svc:only@one";
        flake_rev = "";
        settings_hash = image.version;
        settingsHashIsTheVersion = true;
        settingsHashIsNotTheKey = true;
        settingsHashLength = 16;
      };
    };

  # A name the endpoint's own rule rejects is a refusal, not a mapping: two
  # entries normalised onto one name would collide, and a refusal names the
  # deployment's mistake where it was written.
  testAnUnusableInstanceName = {
    expr = {
      dotted = raises (readOf { instance = "web.one"; } simple);
      outsideTheSet = raises (readOf { instance = "web+one"; } simple);
      wellFormed = raises (readOf { instance = "web_one-1"; } simple);
      rule = {
        dot = reader.acceptsName "web.one";
        plus = reader.acceptsName "web+one";
        underscore = reader.acceptsName "web_one-1";
        leadingDash = reader.acceptsName "-web";
        empty = reader.acceptsName "";
        tooLong = reader.acceptsName (builtins.concatStringsSep "" (builtins.genList (_: "abcdefghij") 13));
        atTheLimit = reader.acceptsName (
          "ab" + builtins.concatStringsSep "" (builtins.genList (_: "cdefghijkl") 12) + "mnopqr"
        );
      };
    };
    expected = {
      dotted = true;
      outsideTheSet = true;
      wellFormed = false;
      rule = {
        dot = false;
        plus = false;
        underscore = true;
        leadingDash = false;
        empty = false;
        tooLong = false;
        atTheLimit = true;
      };
    };
  };

  # A unit file outside the service's namespace is refused too: the endpoint
  # reads `units/` and validates every name in it before it links anything.
  testAUnitNameOutsideTheServicesNamespace = {
    expr = {
      twoInstanceMarkers = raises (
        readOf { } (_: {
          closure = [ borgbackup ];
          units."web@one@two".command = "${borgbackup}/bin/borg serve";
        })
      );
      wellFormedSet = raises (readOf { } withSchedule);
      rule = {
        theServiceItself = reader.acceptsUnit "svc-only" "svc-only.service";
        prefixed = reader.acceptsUnit "svc-only" "svc-only-web.service";
        oneInstance = reader.acceptsUnit "svc-only" "svc-only-web@1.service";
        twoInstances = reader.acceptsUnit "svc-only" "svc-only-web@1@2.service";
        anotherService = reader.acceptsUnit "svc-only" "svc-other-web.service";
        noSuffix = reader.acceptsUnit "svc-only" "svc-only-web";
      };
    };
    expected = {
      twoInstanceMarkers = true;
      wellFormedSet = false;
      rule = {
        theServiceItself = true;
        prefixed = true;
        oneInstance = true;
        twoInstances = false;
        anotherService = false;
        noSuffix = false;
      };
    };
  };

  # A well-formed entry is read, not refused: the refusals below are about
  # names, and a name inside the rule produces an artifact.
  testAWellFormedEntryIsNotRefused = {
    expr = {
      simple = raises (readOf { } simple);
      scheduled = raises (readOf { } withSchedule);
      underscored = raises (readOf { instance = "web_one-1"; } simple);
    };
    expected = {
      simple = false;
      scheduled = false;
      underscored = false;
    };
  };

  # Nothing to evaluate on the machine: the artifact is unit files and one JSON
  # document, so the endpoint links and starts rather than building.
  testNothingIsEvaluatedToActivateIt =
    let
      image = readOf { } withSchedule;
    in
    {
      expr = {
        suffixes = support.planner.util.uniqueStrings (map suffixOf (filesOf image));
        metadataIsADocument = builtins.isAttrs (reader.meta image);
      };
      expected = {
        suffixes = [
          ".service"
          ".timer"
        ];
        metadataIsADocument = true;
      };
    };

  # The artifact names the entry it came from: the endpoint reads the plan key
  # back off `meta.json` rather than being told which entry is running.
  testTheRunningArtifactNamesItsEntry =
    let
      meta = reader.meta (readOf { } simple);
    in
    {
      expr = {
        inherit (meta) name flake_url;
      };
      expected = {
        name = "svc-only";
        flake_url = "plan:svc:only@one";
      };
    };

  # The digest the endpoint compares is a function of the artifact: one changed
  # unit field changes it, and the same entry read twice does not.
  testAChangedUnitFieldIsANewGeneration =
    let
      before = readOf { } simple;
      after = readOf { } changedField;
      again = readOf { } simple;
    in
    {
      expr = {
        changed = before.version != after.version;
        unchanged = before.version == again.version;
        recordedInTheMetadata = (reader.meta after).settings_hash == after.version;
      };
      expected = {
        changed = true;
        unchanged = true;
        recordedInTheMetadata = true;
      };
    };

  # A configuration file is a host path, and this realiser has no step that
  # could assemble one, so the entry is refused where it was written.
  testAnEntryShownAConfigurationFile = {
    expr = {
      refused = raises (readOf { } shownAConfigurationFile);
      theImageRealiserShowsIt =
        map (p: p.kind)
          (reader.reader.read {
            plan = (planned { } shownAConfigurationFile).plan;
            key = "svc:only@one";
            profile = "default";
          }).hostPaths;
    };
    expected = {
      refused = true;
      theImageRealiserShowsIt = [ "configuration-file" ];
    };
  };

  # A generated file reaches a unit as a path on the machine, which is the same
  # refusal for the same reason: no step here checks that it is there.
  testAnEntryShownAGeneratedFile = {
    expr = {
      refused = raises (
        reader.read {
          plan = shownAGeneratedFile.plan;
          key = "svc:only@one";
        }
      );
      theImageRealiserShowsIt =
        map (p: p.kind)
          (reader.reader.read {
            plan = shownAGeneratedFile.plan;
            key = "svc:only@one";
            profile = "trusted";
          }).hostPaths;
    };
    expected = {
      refused = true;
      theImageRealiserShowsIt = [ "generated-file" ];
    };
  };

  # An entry shown no host file is what this realiser is for.
  testAnEntryShownNoHostFileIsBuilt =
    let
      image = readOf { } simple;
    in
    {
      expr = {
        hostPaths = image.hostPaths;
        files = filesOf image;
      };
      expected = {
        hostPaths = [ ];
        files = [ "svc-only-web.service" ];
      };
    };
}
