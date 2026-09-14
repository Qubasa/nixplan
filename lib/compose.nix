# Composition: what a root publishes and which settings a deployment may move.
#
# A root keys each member's settings under that member's own name, including when
# it owns exactly one member, and forwards nothing. Each knob it owns is either a
# default a deployment may overwrite or a fixed value it may not.
{
  util,
  diag,
}:
let
  inherit (builtins) attrNames isAttrs;

  # Composition indexes the value a module returned before the module reading
  # sees it, and `attrNames` on a value of another kind ends the evaluation. The
  # row for that value is the reading's, so the shape is all that is needed here.
  recordOf = value: if isAttrs value then value else { };

  slotsOf = declaration: attrNames ((recordOf declaration).uses or { });

  serviceKeys = [
    "module"
    "defaults"
    "fixed"
    "wire"
  ];
in
rec {
  # The service function a root receives, closed over the settings resolver. The
  # declaration is read once against those settings, so the capabilities a root
  # publishes and the exports a placement produces come from one value.
  service =
    settingsOf: name: args:
    let
      module = args.module;
      defaults = args.defaults or { };
      fixed = args.fixed or { };
      settings = settingsOf { inherit name defaults fixed; };

      # The module's own expression, forced under the recovery its implementation
      # already gets: a module that raises while computing its declaration is one
      # row naming the member, and the empty record it falls back to degrades into
      # the `impl-missing` the reading already writes.
      computed = diag.guard {
        subject = "member:${name}";
        what = "the declaration of member ${util.quote name}";
        fallback = { };
        value = module { settings = settings.values; };
      };
      declaration = computed.value;

      # Whether the deployment moved anything at all. With no deployment knob the
      # member's own values are `settings.values` by construction, so the second
      # reading below is not taken.
      configured = builtins.any (source: source == "deployment") (builtins.attrValues settings.sources);

      # The same module under the values the member declares for itself. Forced
      # for its slot names alone and its rows are dropped: a module that raises on
      # its own defaults is not a shape difference, and the raise it produces
      # against resolved settings is already reported once.
      observed = diag.guard {
        subject = "member:${name}";
        what = "the slots of member ${util.quote name} under its own values";
        fallback = null;
        value = {
          resolved = slotsOf declaration;
          own = slotsOf (module {
            settings = defaults // fixed;
          });
        };
      };
    in
    {
      inherit
        name
        module
        defaults
        fixed
        settings
        declaration
        ;
      # What the root bound this member's slots to: the capability value off a
      # sibling's handle, never a name. A mistyped attribute is a Nix error in
      # the module's own file, and the record the resolver reads back carries the
      # member it came from, so no root ever names an instance.
      wire = args.wire or { };
      slotSet = if configured then observed.value else null;
      declarationRows = computed.rows;
      unknownKeys = util.extraKeys serviceKeys args;
      # A capability of the wrong kind stays a key the root can re-export, and
      # carries no interface: the module earns the reading's row and a wire to it
      # earns the untyped one, where indexing the value would end the evaluation.
      provides = builtins.mapAttrs (
        capability: declared:
        recordOf declared
        // {
          member = name;
          inherit capability;
        }
      ) ((recordOf declaration).provides or { });
    };

  # A root is a function of { service, ... } and nothing else. A root that wants a
  # package passes it through its own closure.
  mkRoot = root: settingsOf: root { service = service settingsOf; };

  # defaults overwritten by the deployment, then fixed on top, with the source of
  # every resolved value recorded.
  resolveSettings =
    {
      subject,
      deploymentFile,
      moduleFile,
      name,
      defaults,
      fixed,
      settings,
    }:
    let
      # The namespace a deployment wrote for this member, read with the shape the
      # rest of this function needs: `attrNames` of a value of another kind ends
      # the evaluation, and the deployment's half is read with the module half's
      # tolerance.
      written = settings.${name} or { };
      malformed = !(builtins.isAttrs written);
      given = if malformed then { } else written;
      givenKeys = attrNames given;
      fixedKeys = attrNames fixed;
      defaultKeys = attrNames defaults;
      writtenFixed = builtins.filter (k: fixed ? ${k}) givenKeys;
      undeclared = builtins.filter (k: !(fixed ? ${k}) && !(defaults ? ${k})) givenKeys;
      applied = removeAttrs given (writtenFixed ++ undeclared);
      values = defaults // applied // fixed;
    in
    {
      inherit values;
      sources = builtins.mapAttrs (
        k: _:
        if fixed ? ${k} then
          "fixed"
        else if applied ? ${k} then
          "deployment"
        else
          "defaults"
      ) values;
      rows =
        util.optional malformed (
          diag.error {
            inherit subject;
            id = "declaration-field-malformed";
            message = "${deploymentFile} declares the settings of ${util.quote name} as a value of type ${builtins.typeOf written}, and the reading needs a record";
            evidence = "the half of a declaration a deployment writes is read with the tolerance the half a module writes is read with, so a value of the wrong kind is a row and the rest of the deployment is still read";
            resolution = "write a record for ${util.quote name} under `settings` in ${deploymentFile}";
          }
        )
        ++ map (
          k:
          diag.error {
            inherit subject;
            id = "settings-fixed-path";
            message = "${deploymentFile} defines ${util.quote "${name}.${k}"}, which ${moduleFile} declares fixed";
            evidence = "a fixed value is a fact the module publishes about itself, so neither value silently wins";
            resolution = "delete the definition from ${deploymentFile}, or make the knob a default in ${moduleFile}";
          }
        ) writtenFixed
        ++ map (
          k:
          diag.error {
            inherit subject;
            id = "settings-undeclared-knob";
            message = "${deploymentFile} defines ${util.quote "${name}.${k}"}, which ${moduleFile} declares neither as a default nor as fixed";
            evidence = "the member declares defaults ${util.quoteList defaultKeys} and fixed values ${util.quoteList fixedKeys}";
            resolution = "declare ${util.quote k} in ${moduleFile}, or delete the definition from ${deploymentFile}";
          }
        ) undeclared;
    };

  namespaceRows =
    {
      subject,
      deploymentFile,
      moduleFile,
      members,
      settings,
    }:
    map (
      k:
      diag.error {
        inherit subject;
        id = "settings-not-member-keyed";
        message = "${deploymentFile} defines ${util.quote k} outside any member's namespace, and a root keys every member's settings under that member's own name";
        evidence = "the root in ${moduleFile} owns ${util.quoteList members}, and a single-member root keys its namespace too";
        resolution = "write `settings.<member>.${k}` in ${deploymentFile}";
      }
    ) (util.subtractList (attrNames settings) members);

  # A slot set that moves with settings is a module publishing a cut, which is a
  # decision a module may take. It is recorded rather than refused because it is
  # the one declaration difference that otherwise leaves no trace: a slot nobody
  # asked for is wired by nobody, and no unwired-slot row misses it.
  slotSetRows =
    {
      subject,
      name,
      deploymentFile,
      observation,
    }:
    let
      removed = util.subtractList observation.own observation.resolved;
      added = util.subtractList observation.resolved observation.own;
      moved = util.sortStrings (removed ++ added);
    in
    util.optional (observation != null && moved != [ ]) (
      diag.warning {
        inherit subject;
        id = "slot-set-settings-derived";
        message = "member ${util.quote name} asks for ${util.quoteList moved} under one reading of its settings and not under the other, so the set of slots it declares is derived from what ${deploymentFile} wrote";
        evidence = "a member's slot set is the module's own statement, and a deployment that cuts a member writes `members.${name}.enable = false` where the whole member is the unit of the cut";
        resolution = "declare the slot unconditionally in ${subject} and branch on the setting inside `impl`, which leaves a wire the planner can refuse, or keep the cut and expect this row";
      }
    );
}
