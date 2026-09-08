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

  changedField = _: {
    closure = [ borgbackup ];
    units.web.command = "${borgbackup}/bin/borg serve --umask 077";
  };

  shownAConfigurationFile = _: {
    closure = [ borgbackup ];
    units.web.command = "${borgbackup}/bin/borg serve";
    configData."/etc/thing.conf" = {
      mode = "0444";
      reload = [ "web" ];
      render = [ { text = "value\n"; } ];
    };
  };

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
