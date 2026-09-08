{ util, diag }:
let
  inherit (builtins) attrNames;

  serviceKeys = [
    "module"
    "defaults"
    "fixed"
  ];
in
rec {
  service =
    settingsOf: name: args:
    let
      module = args.module;
      defaults = args.defaults or { };
      fixed = args.fixed or { };
      settings = settingsOf { inherit name defaults fixed; };
      declaration = module { settings = settings.values; };
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
      unknownKeys = util.extraKeys serviceKeys args;
      provides = builtins.mapAttrs (
        capability: declared:
        declared
        // {
          member = name;
          inherit capability;
        }
      ) (declaration.provides or { });
    };

  mkRoot = root: settingsOf: root { service = service settingsOf; };

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
      given = settings.${name} or { };
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
        map (
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
}
