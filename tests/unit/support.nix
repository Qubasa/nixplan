# Shared scaffolding for the suites: atoms, a leaf module, a root, a machine
# registry and the row helpers every scenario test needs.
#
# A scenario test builds the smallest deployment that produces the row it is
# about, plans it, and asserts on the table. Nothing here reads the filesystem
# except the worked deployment, which arrives as a store path.
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

  # Atoms. Two fields each, because an export in this subset declares a type
  # and a secrecy and nothing else.
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

  # A root over members. `provides` re-exports a member's capability, which is
  # what makes it addressable from outside the instance at all.
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

  # A root with one member called `only`, which is the shape most scenarios
  # need. A single-member root keys its settings namespace too.
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

  # A machine declares what it is: the system it runs and the service manager
  # that runs its units, so a placement on it has a derivable target.
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

  # A second service manager, for the scenarios about a target a module has to
  # ask about before applying a backend's own fields.
  laptop = {
    address = "laptop.example:22";
    tags = [ "everywhere" ];
    system = "aarch64-darwin";
    serviceManager = "launchd";
  };

  # A systemd extension, declared here so two suites can import one value and
  # the identity rule is exercised rather than described.
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

  # Plan a scenario. Every argument the library takes may be overridden.
  planOf =
    args:
    planner.mkPlan (
      {
        inherit machines;
      }
      // args
    );

  # Row helpers.
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

  # Substring rather than regex, so a test can look for `reach = "all"` or a
  # path without escaping anything.
  hasInfix =
    needle: hay:
    let
      n = stringLength needle;
      h = stringLength hay;
    in
    h >= n && any (i: substring i n hay == needle) (genList (i: i) (h - n + 1));

  # Every file under a directory, as a path relative to it. `readDir` is the
  # only way a pure evaluation sees a tree, and both the cross-walk and the
  # layer checks walk one.
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

  # A line with its comment removed. Every text scan over source in these
  # suites is about what a file does, and a sentence in a comment saying the
  # word is not the file doing it.
  codeOf =
    line:
    let
      m = match "([^#]*)#.*" line;
    in
    if m == null then line else head m;

  # The worked deployment of fixtures/minimal-typed-edge/.
  worked = import ./worked.nix { inherit planner folder; };
  workedResult = planner.mkPlan worked.args;
}
