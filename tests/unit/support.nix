{
  planner,
  folder,
  perfSource,
}:
let
  inherit (builtins)
    any
    attrNames
    concatLists
    filter
    genList
    head
    isString
    length
    mapAttrs
    match
    readDir
    split
    stringLength
    substring
    ;

  k = planner.korora;
in
rec {
  inherit planner folder perfSource;
  korora = k;

  publicString = {
    type = k.string;
  };
  publicInt = {
    type = k.int;
  };
  publicUrl = {
    type = k.url;
    secrecy = "public";
  };
  secretFile = {
    type = k.secretRef;
    secrecy = "secret";
  };

  inherit (planner) interface;

  root =
    {
      members,
      provides ? { },
    }:
    { service, ... }:
    let
      services = mapAttrs (name: spec: service name spec) members;
    in
    {
      inherit services;
      provides = mapAttrs (_: ref: services.${ref.member}.provides.${ref.capability}) provides;
    };

  soleRoot =
    {
      module,
      defaults ? { },
      fixed ? { },
      provides ? [ ],
    }:
    root {
      members.only = {
        inherit module defaults fixed;
      };
      provides = builtins.listToAttrs (
        map (cap: {
          name = cap;
          value = {
            member = "only";
            capability = cap;
          };
        }) provides
      );
    };

  machines = {
    one = {
      address = "one.example:22";
      tags = [ "everywhere" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    two = {
      address = "two.example:22";
      tags = [ "everywhere" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };

  laptop = {
    address = "laptop.example:22";
    tags = [ "everywhere" ];
    system = "aarch64-darwin";
    serviceManager = "launchd";
  };

  systemdService = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields = {
      protectSystem = {
        type = k.enum "protect-system" [
          "no"
          "yes"
          "full"
          "strict"
        ];
      };
      stateDirectory = {
        type = k.string;
      };
    };
  };

  planOf =
    args:
    planner.mkPlan (
      {
        inherit machines;
      }
      // args
    );

  rowIds = result: map (r: r.id) result.diagnostics;
  rowsById = id: result: filter (r: r.id == id) result.diagnostics;
  countById = id: result: length (rowsById id result);
  hasRow = id: result: rowsById id result != [ ];
  subjectsById = id: result: map (r: r.subject) (rowsById id result);
  severityById =
    id: result:
    let
      rows = rowsById id result;
    in
    if rows == [ ] then null else (head rows).severity;
  messageById =
    id: result:
    let
      rows = rowsById id result;
    in
    if rows == [ ] then null else (head rows).message;
  evidenceById =
    id: result:
    let
      rows = rowsById id result;
    in
    if rows == [ ] then null else (head rows).evidence;

  hasInfix =
    needle: hay:
    let
      n = stringLength needle;
      h = stringLength hay;
    in
    h >= n && any (i: substring i n hay == needle) (genList (i: i) (h - n + 1));

  filesUnder =
    dir:
    let
      entries = readDir dir;
    in
    concatLists (
      map (
        name:
        if entries.${name} == "directory" then
          map (rest: "${name}/${rest}") (filesUnder (dir + "/${name}"))
        else
          [ name ]
      ) (attrNames entries)
    );

  lines = text: filter isString (split "\n" text);

  codeOf =
    line:
    let
      m = match "([^#]*)#.*" line;
    in
    if m == null then line else head m;

  worked = import ./worked.nix { inherit planner folder; };
  workedResult = planner.mkPlan worked.args;
}
