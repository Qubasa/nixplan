{
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
    ;

  inherit (support) raises;
  inherit (support.worked) borgbackup;

  realiser = support.realiser {
    inherit (support) assemble;
    inherit imageSource flakeletSource operatorSource;
  };

  inherit (realiser) imageReader planned;

  reader = realiser.flakeletReader;

  # The layer that reports each of this realiser's refusals as a row first.
  build = realiser.operatorReader;

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

  readOf = args: realiser.readOf ({ read = reader.read; } // args);

  simple = support.serving "web";

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

  shownAGeneratedFile = support.valuePlan {
    unit = "web";
    openIt = true;
  };

  # A recipe naming a delivered path: its bytes exist on no machine until that
  # path is written, which is the one case this realiser still refuses.
  shownARefBearingFile = support.valuePlan {
    unit = "web";
    extra = vars: {
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
  shownAnOwnedGeneratedFile = support.valuePlan {
    unit = "web";
    openIt = true;
    fileArgs = {
      owner = "postgres";
      group = "postgres";
      mode = "0440";
    };
  };

  # One unit that says how it is probed. `extra` is what the probed unit
  # declares beside the pair, so a test asking what the probe does and does not
  # inherit states only that.
  probing =
    {
      command ? "${borgbackup}/bin/borg check",
      timeout ? "30s",
      extra ? { },
    }:
    _: {
      closure = [ borgbackup ];
      units.web = {
        command = "${borgbackup}/bin/borg serve";
        probe = command;
        probeTimeout = timeout;
      }
      // extra;
    };

  # Two members of one instance, one probed and one not, so an edit to the
  # probe is asked of the artifact beside it as well.
  pair =
    command:
    support.planOf {
      instances.svc = {
        module = support.root {
          members.only.module = _: { impl = probing { inherit command; }; };
          members.side.module = _: { impl = support.serving "web"; };
        };
        placement.every.only.machines = [ "one" ];
        placement.every.side.machines = [ "one" ];
      };
    };

  # The derived file's text among the ones a realiser publishes, read off the
  # published set rather than off the renderer: what a test asserts is what a
  # builder writes, which is the claim about the wrappers.
  probeTextOf =
    rendered: image:
    builtins.head (
      map (f: f.text) (filter (f: f.file == imageReader.probeFileName image.name) rendered)
    );

  probeOf = image: probeTextOf (reader.renderedUnits image) image;

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

  # The endpoint links a file by the name it is handed, so a second line of that
  # name is a directive no module wrote.
  testAUnitNameCarryingALineBreakIsRefusedByTheRestatedRule =
    let
      forged = _: {
        closure = [ borgbackup ];
        units."main\nConditionPathExists=/nonexistent".command = "${borgbackup}/bin/borg serve";
      };
      message = messageAbove { } forged;
    in
    {
      expr = {
        rule = reader.acceptsUnit "svc-only" "svc-only-main\nConditionPathExists=/nonexistent.service";
        wellFormed = reader.acceptsUnit "svc-only" "svc-only-main.service";
        refused = raises (readOf { } forged);
        rowAbove = rowsAbove { } forged;
        theRowNamesTheEntry = support.hasInfix "svc:only@one" message;
        theRowNamesTheName = support.hasInfix "ConditionPathExists=/nonexistent.service" message;
        theRowStatesTheSameRule = support.hasInfix (reader.unitRule "svc-only") message;
      };
      expected = {
        rule = false;
        wellFormed = true;
        refused = true;
        rowAbove = [ "operator-entry-name-refused" ];
        theRowNamesTheEntry = true;
        theRowNamesTheName = true;
        theRowStatesTheSameRule = true;
      };
    };

  # The rules the two realisers hold differ, and this unit file is where they do:
  # the image builder's store name set carries no `@`, and this endpoint's own
  # rule reads one as systemd's instance marker.
  testAUnitThisEndpointAcceptsAndTheImageBuilderRefuses =
    let
      instanced = _: {
        closure = [ borgbackup ];
        units."web@one".command = "${borgbackup}/bin/borg serve";
      };
    in
    {
      expr = {
        refused = raises (readOf { } instanced);
        rowAbove = rowsAbove { } instanced;
        file = (readOf { } instanced).units."web@one".file;
        theImageBuildersRule = imageReader.acceptsUnit "svc-only" "svc-only-web@one.service";
        thisEndpointsRule = reader.acceptsUnit "svc-only" "svc-only-web@one.service";
      };
      expected = {
        refused = false;
        rowAbove = [ ];
        file = "svc-only-web@one.service";
        theImageBuildersRule = false;
        thisEndpointsRule = true;
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

  # The prefix the record publishes and the url the artifact carries are one
  # binding, so a command reading the record alone recognises an answer this
  # endpoint gave and reads the plan key back out of it.
  testThePublishedPrefixIsTheOneTheArtifactCarries =
    let
      image = readOf { } simple;
      url = (reader.meta image).flake_url;
      prefix = reader.holdings.urlPrefix;
    in
    {
      expr = {
        holdings = reader.holdings;
        oneString = url == "${prefix}${image.key}";
        theHeadOfTheUrl = builtins.substring 0 (builtins.stringLength prefix) url;
        whatFollowsIt = builtins.substring (builtins.stringLength prefix) (builtins.stringLength url) url;
        # Published beside the rules the deployment reading already asks this
        # realiser for, which is how the record reaches it.
        besideTheRules = {
          nameRule = reader ? nameRule;
          unitRule = reader ? unitRule;
          holdings = reader ? holdings;
        };
      };
      expected = {
        holdings = {
          urlPrefix = "plan:";
        };
        oneString = true;
        theHeadOfTheUrl = "plan:";
        whatFollowsIt = "svc:only@one";
        besideTheRules = {
          nameRule = true;
          unitRule = true;
          holdings = true;
        };
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

  testThePublishedScopesNameTheSystemScopeAlone = {
    expr = {
      scopes = reader.scopes;
      # Published beside the two rules the deployment reading already asks this
      # realiser for, which is how the crossing above reaches it.
      besideTheRules = {
        nameRule = reader ? nameRule;
        unitRule = reader ? unitRule;
        scopes = reader ? scopes;
      };
      # The image realiser is the one that realises an account's deployment.
      theOtherRealiser = imageReader.scopes;
    };
    expected = {
      scopes = [ "system" ];
      besideTheRules = {
        nameRule = true;
        unitRule = true;
        scopes = true;
      };
      theOtherRealiser = [
        "system"
        "user"
      ];
    };
  };

  testAnEntryPlacedInUserScopeIsRefusedBeforeBytesExist =
    let
      rows = (build.read { plan = (planned userScoped simple).plan; }).rows;
      row = builtins.head rows;
    in
    {
      expr = {
        refused = raises (readOf userScoped simple);
        # The same entry on a machine stating nothing is the system scope, which
        # this realiser realises.
        systemScopeIsRealised = raises (readOf { } simple);
        rowAbove = map (r: r.id) rows;
        theAccountPairsThem = reader.accounts.scopeUnsupported.id;
        names = map (needle: support.hasInfix needle row.message) [
          "svc:only@account"
          "`user`"
        ];
        # The sentence the raise prints is the realiser's published rule, so the
        # upstream facts the limit rests on are read off it rather than off the
        # row, which states the scopes.
        theSentenceNamesTheUpstreamFacts = map (needle: support.hasInfix needle reader.scopeRule) [
          "/run/systemd/system"
          "systemd.rs:13"
          "/var/lib/flakelet"
        ];
      };
      expected = {
        refused = true;
        systemScopeIsRealised = false;
        rowAbove = [ "operator-entry-scope-unsupported" ];
        theAccountPairsThem = "operator-entry-scope-unsupported";
        names = [
          true
          true
        ];
        theSentenceNamesTheUpstreamFacts = [
          true
          true
          true
        ];
      };
    };

  testAProbedEntryCarriesOneMoreUnitFile =
    let
      image = readOf { } (probing { });
      derived = imageReader.probeFileName image.name;
    in
    {
      expr = {
        files = map (f: f.file) (reader.renderedUnits image);
        inherit derived;
        theServiceNameAndTheSuffix = derived == "${image.name}-health.service";
        unprobed = map (f: f.file) (reader.renderedUnits (readOf { } simple));
      };
      expected = {
        files = [
          "svc-only-web.service"
          "svc-only-health.service"
        ];
        derived = "svc-only-health.service";
        theServiceNameAndTheSuffix = true;
        unprobed = [ "svc-only-web.service" ];
      };
    };

  # `Requires=` beside `After=` is what makes starting the probe on a machine
  # whose service is not active fail rather than report success, which is the
  # whole gate.
  testTheDerivedProbeUnitIsOrderedAgainstTheUnitItProbes =
    let
      text = probeOf (readOf { } (probing { }));
    in
    {
      expr = {
        inherit text;
        runsOnce = support.hasInfix "\nType=oneshot\n" text;
        ordered = support.hasInfix "\nAfter=svc-only-web.service\n" text;
        required = support.hasInfix "\nRequires=svc-only-web.service\n" text;
        bound = filter (l: support.hasInfix "TimeoutStartSec" l) (support.lines text);
        # The bound is the plan's and nothing else's: a probe declaring another
        # renders another, and no default is written where the plan states one.
        anotherBound = filter (l: support.hasInfix "TimeoutStartSec" l) (
          support.lines (
            probeOf (
              readOf { } (probing {
                timeout = "2min";
              })
            )
          )
        );
      };
      expected = {
        text = ''
          [Unit]
          Description=svc:only web probe
          After=svc-only-web.service
          Requires=svc-only-web.service

          [Service]
          ExecStart=${borgbackup}/bin/borg check
          Type=oneshot
          TimeoutStartSec=30s
        '';
        runsOnce = true;
        ordered = true;
        required = true;
        bound = [ "TimeoutStartSec=30s" ];
        anotherBound = [ "TimeoutStartSec=2min" ];
      };
    };

  # A probe that reads what the service reads is the case the field exists for,
  # so the derived unit is the probed unit's account and the readability
  # question is the one already answered for it.
  testTheDerivedProbeUnitTakesTheProbedUnitsAccount =
    let
      declaring = readOf { } (probing {
        extra.user = "borg";
      });
      silent = readOf { } (probing { });
      accounts = text: filter (l: support.hasInfix "User=" l) (support.lines text);
    in
    {
      expr = {
        declared = accounts (probeOf declaring);
        theProbedUnitDeclaresIt = accounts (reader.renderUnit declaring "web");
        undeclared = accounts (probeOf silent);
        theProbedUnitDeclaresNone = accounts (reader.renderUnit silent "web");
      };
      expected = {
        declared = [ "User=borg" ];
        theProbedUnitDeclaresIt = [ "User=borg" ];
        undeclared = [ ];
        theProbedUnitDeclaresNone = [ ];
      };
    };

  # The endpoint starts it by name after switching, and an `[Install]` would
  # queue it at every boot and after `flakelet boot` as well - the reason a
  # scheduled unit's service carries none either.
  testTheDerivedProbeUnitCarriesNoInstallSection =
    let
      image = readOf { } (probing { });
      text = probeOf image;
    in
    {
      expr = {
        sections = lastSection text;
        install = support.hasInfix "[Install]" text;
        wantedBy = support.hasInfix "WantedBy" text;
        # The file this realiser publishes is the shared reading's own text, so
        # neither of this realiser's two wrappers is in the probe's path.
        renderedByNeitherWrapper = text == imageReader.renderProbe image;
        theUnitItProbesIsWanted = support.hasInfix "\n[Install]\nWantedBy=multi-user.target\n" (
          reader.renderUnit image "web"
        );
      };
      expected = {
        sections = [
          "[Unit]"
          "[Service]"
        ];
        install = false;
        wantedBy = false;
        renderedByNeitherWrapper = true;
        theUnitItProbesIsWanted = true;
      };
    };

  # A runtime directory declared on a job that exits is deleted when it exits,
  # which would take the probed unit's own with it, and a directory a static
  # account may read needs no declaration to be read.
  testTheDerivedProbeUnitClaimsNoDirectory =
    let
      declaring = probing {
        extra = {
          runtimeDirectory = [ "web" ];
          runtimeDirectoryMode = "0700";
          stateDirectory = [ "web" ];
          cacheDirectory = [ "web" ];
        };
      };
      image = readOf { } declaring;
      kinds =
        text:
        filter (needle: support.hasInfix needle text) [
          "CacheDirectory"
          "RuntimeDirectory"
          "StateDirectory"
        ];
    in
    {
      expr = {
        declaredByTheProbe = kinds (probeOf image);
        declaredByTheUnitItProbes = kinds (reader.renderUnit image "web");
        # And no claimant is added to the index the shared-directory row reads,
        # so that row keeps meaning two declarations rather than one
        # declaration and one derivation.
        rows = map (r: r.id) (planned { } declaring).result.diagnostics;
        rowAbove = rowsAbove { } declaring;
      };
      expected = {
        declaredByTheProbe = [ ];
        declaredByTheUnitItProbes = [
          "CacheDirectory"
          "RuntimeDirectory"
          "StateDirectory"
        ];
        rows = [ ];
        rowAbove = [ ];
      };
    };

  # The derived name is held to the endpoint's unit rule by existing: it comes
  # off the one derivation `read` refuses a name outside the rule off.
  testTheDerivedNameIsOneTheEndpointAccepts =
    let
      probedUnits = {
        web = {
          command = "true";
          probe = "true";
          probeTimeout = "30s";
        };
      };
      admitted = [
        "svc-only"
        "a"
        "web_one-1"
        "x0"
      ];
    in
    {
      expr = {
        acceptedByTheEndpoint = reader.acceptsUnit "svc-only" "svc-only-health.service";
        # Every service name the endpoint's own name rule admits derives a probe
        # file its unit rule admits.
        refusedOfAnAdmittedName = filter (
          name: reader.acceptsName name && !(reader.acceptsUnit name (imageReader.probeFileName name))
        ) admitted;
        # And the list `read` holds to that rule is the one carrying it.
        derivedFiles = imageReader.unitFilesOf "svc-only" probedUnits;
        refusedAmongThem = filter (file: !(reader.acceptsUnit "svc-only" file)) (
          imageReader.unitFilesOf "svc-only" probedUnits
        );
        # The image builder's stricter rule admits it too.
        acceptedByTheOtherRealiser = imageReader.acceptsUnit "svc-only" "svc-only-health.service";
        built = raises (readOf { } (probing { }));
      };
      expected = {
        acceptedByTheEndpoint = true;
        refusedOfAnAdmittedName = [ ];
        derivedFiles = [
          "svc-only-web.service"
          "svc-only-health.service"
        ];
        refusedAmongThem = [ ];
        acceptedByTheOtherRealiser = true;
        built = false;
      };
    };

  # A probe is a unit field, so it is in the entry's key and in the artifact's
  # content-derived version: the endpoint activates the changed artifact as a
  # new generation rather than reporting that there is nothing to do.
  testAChangedProbeMovesTheArtifactsIdentity =
    let
      readAt =
        command: key:
        reader.read {
          plan = (pair command).plan;
          inherit key;
        };
      before = readAt "${borgbackup}/bin/borg check" "svc:only@one";
      after = readAt "${borgbackup}/bin/borg check --repository-only" "svc:only@one";
      keyAt = command: key: (pair command).plan.${key}.key;
      beside = command: readAt command "svc:side@one";
    in
    {
      expr = {
        keyMoved =
          keyAt "${borgbackup}/bin/borg check" "svc:only@one"
          != keyAt "${borgbackup}/bin/borg check --repository-only" "svc:only@one";
        versionMoved = before.version != after.version;
        recordedInTheMetadata = (reader.meta before).settings_hash != (reader.meta after).settings_hash;
        # No other entry's artifact moves: the fields are the probed unit's.
        theOtherEntryStands =
          (beside "${borgbackup}/bin/borg check").version
          == (beside "${borgbackup}/bin/borg check --repository-only").version;
        theOtherEntrysKeyStands =
          keyAt "${borgbackup}/bin/borg check" "svc:side@one"
          == keyAt "${borgbackup}/bin/borg check --repository-only" "svc:side@one";
      };
      expected = {
        keyMoved = true;
        versionMoved = true;
        recordedInTheMetadata = true;
        theOtherEntryStands = true;
        theOtherEntrysKeyStands = true;
      };
    };

  # What the deployment record publishes for the artifact, which is what an
  # endpoint comparing the active generation's unit files against this build's
  # compares: a generation built before the probe existed reads as not running
  # this build's units.
  testAProbeIsPublishedAmongTheArtifactsUnitFiles =
    let
      publishedOf =
        implementation:
        (build.read { plan = (planned { } implementation).plan; }).manifest.entries."svc:only@one".units;
    in
    {
      expr = {
        published = publishedOf (probing { });
        unprobed = publishedOf simple;
        # The published list and the files the artifact carries are one list.
        carried = support.planner.util.sortStrings (
          map (f: f.file) (reader.renderedUnits (readOf { } (probing { })))
        );
      };
      expected = {
        published = [
          "svc-only-health.service"
          "svc-only-web.service"
        ];
        unprobed = [ "svc-only-web.service" ];
        carried = [
          "svc-only-health.service"
          "svc-only-web.service"
        ];
      };
    };

  # The one thing the two realisers differ about for a unit file is the install
  # section, and the probe carries none, so it is rendered once and the two
  # cannot drift about the file that decides an activation.
  testTheProbeUnitIsTheOneFileBothRealisersRenderAlike =
    let
      p = planned { } (probing { });
      asService = reader.read { inherit (p) plan key; };
      asImage = imageReader.read {
        inherit (p) plan key;
        profile = "trusted";
      };
      served = probeTextOf (reader.renderedUnits asService) asService;
      imaged = probeTextOf (imageReader.renderedUnits asImage) asImage;
    in
    {
      expr = {
        oneText = served == imaged;
        neitherCarriesAnInstallSection = [
          (support.hasInfix "[Install]" served)
          (support.hasInfix "[Install]" imaged)
        ];
        # The probed unit's own file is where the two do differ, so the equality
        # above is a property of the probe and not of the two readings.
        andTheUnitFilesDiffer = reader.renderUnit asService "web" != imageReader.renderUnit asImage "web";
      };
      expected = {
        oneText = true;
        neitherCarriesAnInstallSection = [
          false
          false
        ];
        andTheUnitFilesDiffer = true;
      };
    };
}
