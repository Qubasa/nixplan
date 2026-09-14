{
  planner,
  support,
  flakeletSource,
  imageSource,
  operatorSource,
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

  # The reading is handed the same assembly the builder hands it, so a
  # configuration file of nothing but literals is a store path here too. This
  # layer realises nothing, so the stand-in is keyed by the bytes.
  assemble = name: text: "/nix/store/${planner.util.shortHash text}-${name}";

  imageReader = import (imageSource + "/read.nix") { inherit planner assemble; };

  reader = import (flakeletSource + "/read.nix") {
    inherit planner;
    reader = imageReader;
  };

  # The layer that reports each of this realiser's refusals as a row first.
  build = import (operatorSource + "/read.nix") {
    inherit planner imageReader;
    flakeletReader = reader;
  };

  rowsAbove =
    args: implementation:
    let
      p = planned args implementation;
    in
    builtins.sort (a: b: a < b) (map (r: r.id) (build.read { inherit (p) plan; }).rows);

  messageAbove =
    args: implementation:
    let
      p = planned args implementation;
      rows = (build.read { inherit (p) plan; }).rows;
    in
    if rows == [ ] then "" else (builtins.head rows).message;

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

  # deepSeq, because a refusal guards fields a lazy read would never force.
  raises = value: !(tryEval (builtins.deepSeq value value)).success;

  simple = _: {
    closure = [ borgbackup ];
    units.web.command = "${borgbackup}/bin/borg serve";
  };

  reloads = _: {
    closure = [ borgbackup ];
    units.web = {
      command = "${borgbackup}/bin/borg serve";
      reloadCommand = "${borgbackup}/bin/borg reload";
    };
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
    varsState."svc:vars/hostKey@one"."key" = {
      present = true;
      content = "PRIVATE-KEY-BYTES";
    };
  };

  # A recipe naming a delivered path: its bytes exist on no machine until that
  # path is written, which is the one case this realiser still refuses.
  shownARefBearingFile = planOf {
    instances.svc = {
      module = soleRoot {
        module = _: {
          vars.hostKey.files."key".secrecy = "secret";
          impl =
            { vars, ... }:
            {
              closure = [ borgbackup ];
              units.web.command = "${borgbackup}/bin/borg serve";
              configData."/etc/agent.conf" = {
                mode = "0400";
                reload = [ "web" ];
                render = [
                  { text = "key_file = "; }
                  { ref = vars.hostKey."key".path; }
                ];
              };
            };
        };
      };
      placement.every.only.machines = [ "one" ];
    };
    varsState."svc:vars/hostKey@one"."key" = {
      present = true;
      content = "PRIVATE-KEY-BYTES";
    };
  };

  # A configuration file that is someone else's store object already.
  shownASourceFile = _: {
    closure = [ borgbackup ];
    units.web.command = "${borgbackup}/bin/borg serve";
    configData."/etc/thing.conf" = {
      mode = "0444";
      reload = [ "web" ];
      source = "${borgbackup}/share/thing.conf";
    };
  };

  # A configuration file of literals whose record defaults to the one a store
  # object carries, so a caller states only the field that moves off it.
  statingRecord =
    {
      owner ? null,
      group ? null,
      mode ? "0444",
    }:
    _: {
      closure = [ borgbackup ];
      units.web.command = "${borgbackup}/bin/borg serve";
      configData."/etc/thing.conf" = {
        inherit mode;
        reload = [ "web" ];
        render = [ { text = "value\n"; } ];
      }
      // (if owner == null then { } else { inherit owner; })
      // (if group == null then { } else { inherit group; });
    };

  # A delivered generated file whose record names an account other than the
  # superuser: the delivery installs it, not this realiser.
  shownAnOwnedGeneratedFile = planOf {
    instances.svc = {
      module = soleRoot {
        module = _: {
          vars.hostKey.files."key" = {
            secrecy = "secret";
            owner = "postgres";
            group = "postgres";
            mode = "0440";
          };
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
    varsState."svc:vars/hostKey@one"."key" = {
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

  # The timer carries the install section and the service does not. Otherwise the job
  # runs once at deploy time and again on its schedule.
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

  # A reload is the caller's to issue, and it is only issuable where the unit
  # file carries the directive: a unit that declared none is restarted instead,
  # and neither needs the entry to be activated again.
  testAUnitDeclaringAReloadCommand =
    let
      declaring = reader.renderUnit (readOf { } reloads) "web";
      silent = reader.renderUnit (readOf { } simple) "web";
    in
    {
      expr = {
        rendered = support.hasInfix "\nExecReload=${borgbackup}/bin/borg reload\n" declaring;
        absentWhereUndeclared = support.hasInfix "ExecReload" silent;
        sameOtherwise = lastSection declaring == lastSection silent;
      };
      expected = {
        rendered = true;
        absentWhereUndeclared = false;
        sameOtherwise = true;
      };
    };

  # An artifact is unit files and a metadata document. What starts, reloads or
  # restarts anything is the endpoint reading them, so nothing this realiser
  # produces names a service manager verb.
  testTheRealiserIssuesNothing =
    let
      image = readOf { } reloads;
      texts = map (unitName: reader.renderUnit image unitName) (attrNames image.units);
      names = [
        "systemctl"
        "try-restart"
        "try-reload-or-restart"
      ];
    in
    {
      expr = {
        issued = filter (verb: builtins.any (text: support.hasInfix verb text) texts) names;
        metadataIssuesNothing = attrNames (reader.meta image);
      };
      expected = {
        issued = [ ];
        metadataIssuesNothing = [
          "flake_rev"
          "flake_url"
          "name"
          "settings_hash"
          "version"
        ];
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
      rowAbove = rowsAbove { instance = "web.one"; } simple;
      theRowStatesTheSameRule = support.hasInfix reader.nameRule (
        messageAbove { instance = "web.one"; } simple
      );
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
      rowAbove = [ "operator-entry-name-refused" ];
      theRowStatesTheSameRule = true;
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
      rowAbove = rowsAbove { } (_: {
        closure = [ borgbackup ];
        units."web@one@two".command = "${borgbackup}/bin/borg serve";
      });
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
      rowAbove = [ "operator-entry-name-refused" ];
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
      noRowAbove = rowsAbove { } simple ++ rowsAbove { instance = "web_one-1"; } simple;
    };
    expected = {
      simple = false;
      scheduled = false;
      underscored = false;
      noRowAbove = [ ];
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

  # The base scenario, narrowed to the case that still holds: a recipe naming a
  # delivered path is bytes that exist on no machine until that path is written,
  # and this realiser runs no step there to write it.
  testAnEntryShownAConfigurationFile =
    let
      key = "svc:only@one";
      refusal = raises (
        reader.read {
          inherit key;
          plan = shownARefBearingFile.plan;
        }
      );
      rows = (build.read { plan = shownARefBearingFile.plan; }).rows;
    in
    {
      expr = {
        refused = refusal;
        rowAbove = builtins.sort (a: b: a < b) (map (r: r.id) rows);
        theRowNamesThePath = support.hasInfix "/etc/agent.conf" (builtins.head rows).message;
        theRowNamesTheReference = support.hasInfix "/run/vars/svc/hostKey/key" (builtins.head rows).message;
        theImageRealiserShowsIt =
          map (p: p.kind)
            (imageReader.read {
              inherit key;
              plan = shownARefBearingFile.plan;
              profile = "trusted";
            }).hostPaths;
      };
      expected = {
        refused = true;
        rowAbove = [ "operator-entry-path-not-assembled" ];
        theRowNamesThePath = true;
        theRowNamesTheReference = true;
        theImageRealiserShowsIt = [
          "configuration-file"
          "generated-file"
        ];
      };
    };

  testAConfigurationFileReferencingADeliveredPath =
    let
      rows = (build.read { plan = shownARefBearingFile.plan; }).rows;
    in
    {
      expr = {
        refused = raises (
          reader.read {
            key = "svc:only@one";
            plan = shownARefBearingFile.plan;
          }
        );
        statesWhenTheBytesExist = support.hasInfix "bytes exist before the entry is activated" (builtins.head rows)
        .message;
        rowIds = map (r: r.id) rows;
      };
      expected = {
        refused = true;
        statesWhenTheBytesExist = true;
        rowIds = [ "operator-entry-path-not-assembled" ];
      };
    };

  testAConfigurationFileAssembledFromLiterals =
    let
      image = readOf { } shownAConfigurationFile;
      shown = builtins.head image.hostPaths;
    in
    {
      expr = {
        rowAbove = rowsAbove { } shownAConfigurationFile;
        disposition = shown.disposition;
        fromTheStore = support.hasInfix "/nix/store/" shown.from;
        boundInTheUnit = support.hasInfix "BindReadOnlyPaths=${shown.from}:/etc/thing.conf" (
          reader.renderUnit image "web"
        );
      };
      expected = {
        rowAbove = [ ];
        disposition = "literal";
        fromTheStore = true;
        boundInTheUnit = true;
      };
    };

  testAConfigurationFileCopiedFromAStorePath =
    let
      image = readOf { } shownASourceFile;
      shown = builtins.head image.hostPaths;
    in
    {
      expr = {
        rowAbove = rowsAbove { } shownASourceFile;
        disposition = shown.disposition;
        from = shown.from;
        boundInTheUnit = support.hasInfix "BindReadOnlyPaths=${shown.from}:/etc/thing.conf" (
          reader.renderUnit image "web"
        );
      };
      expected = {
        rowAbove = [ ];
        disposition = "source";
        from = "${borgbackup}/share/thing.conf";
        boundInTheUnit = true;
      };
    };

  # The acceptance rests on when the bytes arrive, not on the file's kind: the
  # generated file is delivered before activation, so it is shown from its own path.
  testADeliveredGeneratedFileIsStillAccepted =
    let
      image = reader.read {
        key = "svc:only@one";
        plan = shownAGeneratedFile.plan;
      };
    in
    {
      expr = {
        accepted = !(raises image);
        shown = map (p: {
          inherit (p) kind;
          isItsOwnSource = p.from == p.path;
        }) image.hostPaths;
      };
      expected = {
        accepted = true;
        shown = [
          {
            kind = "generated-file";
            isItsOwnSource = true;
          }
        ];
      };
    };

  testAnEntryWithNoConfigurationFileIsUnchanged =
    let
      image = readOf { } simple;
    in
    {
      expr = {
        shown = image.hostPaths;
        assembled = filter (p: p.kind == "configuration-file") image.hostPaths;
      };
      expected = {
        shown = [ ];
        assembled = [ ];
      };
    };

  # A generated file's host path is its own source rather than a staging
  # destination, and its bytes arrive by delivery before the entry is activated,
  # so there is no step here to be missing.
  testAnEntryShownAGeneratedFile =
    let
      image = reader.read {
        plan = shownAGeneratedFile.plan;
        key = "svc:only@one";
      };
    in
    {
      expr = {
        built = image.name;
        shown = map (p: {
          inherit (p) kind;
          isItsOwnSource = p.from == p.path;
        }) image.hostPaths;
        renderedUnitNamesThePath = support.hasInfix "/run/vars/svc/hostKey/key" (
          reader.renderUnit image "web"
        );
        bytesAnywhere = support.hasInfix "PRIVATE-KEY-BYTES" (builtins.toJSON image);
      };
      expected = {
        built = "svc-only";
        shown = [
          {
            kind = "generated-file";
            isItsOwnSource = true;
          }
        ];
        renderedUnitNamesThePath = true;
        bytesAnywhere = false;
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

  testAFlakeletUnitCarriesTheDirectoryAndConditionDirectives =
    let
      declaring = _: {
        closure = [ borgbackup ];
        units.web = {
          command = "${borgbackup}/bin/borg serve";
          stateDirectory = [ "myapp" ];
          stateDirectoryMode = "0700";
          startIfPathAbsent = "/var/lib/myapp/VERSION";
        };
      };
      text = reader.renderUnit (readOf { } declaring) "web";
    in
    {
      expr = {
        directives = map (needle: support.hasInfix needle text) [
          "StateDirectory=myapp"
          "StateDirectoryMode=0700"
          "ConditionPathExists=!/var/lib/myapp/VERSION"
        ];
        install = lastSection text;
        # No second mapping here: the directive names come from the one table.
        table = [
          reader.reader.unitDirectives.stateDirectory
          reader.reader.unitDirectives.startIfPathAbsent
        ];
      };
      expected = {
        directives = [
          true
          true
          true
        ];
        install = [
          "[Unit]"
          "[Service]"
          "[Install]"
        ];
        table = [
          "StateDirectory"
          "ConditionPathExists"
        ];
      };
    };

  testAUnitDeclaringNoneOfTheNewFieldsIsByteIdentical =
    let
      text = reader.renderUnit (readOf { } simple) "web";
    in
    {
      expr = {
        inherit text;
        names = map (needle: support.hasInfix needle text) [
          "Directory"
          "Condition"
        ];
      };
      expected = {
        text = ''
          [Unit]
          Description=svc:only web

          [Service]
          ExecStart=${borgbackup}/bin/borg serve

          [Install]
          WantedBy=multi-user.target
        '';
        names = [
          false
          false
        ];
      };
    };

  testAnEntryShownAConfigurationFileStatingAnOwnership =
    let
      owned = statingRecord {
        owner = "postgres";
        group = "postgres";
      };
      rows = (build.read { plan = (planned { } owned).plan; }).rows;
      row = builtins.head rows;
    in
    {
      expr = {
        refused = raises (readOf { } owned);
        rowAbove = map (r: r.id) rows;
        names = map (needle: support.hasInfix needle row.message) [
          "svc:only@one"
          "/etc/thing.conf"
          "postgres:postgres at mode 0444"
          "root:root at mode 0444"
        ];
        resolutionNamesBothWaysOut = map (needle: support.hasInfix needle row.resolution) [
          "root:root at mode 0444"
          "state `image`"
        ];
      };
      expected = {
        refused = true;
        rowAbove = [ "operator-entry-path-not-installable" ];
        names = [
          true
          true
          true
          true
        ];
        resolutionNamesBothWaysOut = [
          true
          true
        ];
      };
    };

  testAnEntryShownAFileAtAModeNoStoreObjectHas =
    let
      closed = statingRecord { mode = "0600"; };
      rows = (build.read { plan = (planned { } closed).plan; }).rows;
      row = builtins.head rows;
    in
    {
      expr = {
        refused = raises (readOf { } closed);
        rowAbove = map (r: r.id) rows;
        names = map (needle: support.hasInfix needle row.message) [
          "svc:only@one"
          "/etc/thing.conf"
          "root:root at mode 0600"
          "root:root at mode 0444"
        ];
      };
      expected = {
        refused = true;
        rowAbove = [ "operator-entry-path-not-installable" ];
        names = [
          true
          true
          true
          true
        ];
      };
    };

  testAnEntryShownAFileWhoseRecordTheStoreCarries =
    let
      carried = statingRecord { };
      image = readOf { } carried;
      shown = builtins.head image.hostPaths;
    in
    {
      expr = {
        rowAbove = rowsAbove { } carried;
        accepted = !(raises image);
        install = shown.install;
        boundFromTheArtifact = support.hasInfix "BindReadOnlyPaths=${shown.from}:/etc/thing.conf" (
          reader.renderUnit image "web"
        );
        fromTheStore = support.hasInfix "/nix/store/" shown.from;
      };
      expected = {
        rowAbove = [ ];
        accepted = true;
        install = false;
        boundFromTheArtifact = true;
        fromTheStore = true;
      };
    };

  # A generated file's record is installed by whoever delivers the bytes, and its
  # bytes arrive before activation, so this realiser is asked neither question.
  testADeliveredFilesRecordIsNotThisRealisersToInstall =
    let
      image = reader.read {
        plan = shownAnOwnedGeneratedFile.plan;
        key = "svc:only@one";
      };
      shown = builtins.head image.hostPaths;
    in
    {
      expr = {
        accepted = !(raises image);
        kind = shown.kind;
        isItsOwnSource = shown.from == shown.path;
        record = builtins.head (map (g: "${g.owner}:${g.group} at mode ${g.mode}") image.generated);
        recordIsAsked = reader.acceptsRecord shown;
      };
      expected = {
        accepted = true;
        kind = "generated-file";
        isItsOwnSource = true;
        record = "postgres:postgres at mode 0440";
        recordIsAsked = true;
      };
    };
}
