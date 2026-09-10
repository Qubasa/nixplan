# Reading one plan as a configuration for the external secret generator.
#
# The generator's contract is a JSON object it consumes without evaluating any of
# this library's Nix: one store entry per generated value, a restricted name per
# entry, and one program per entry. It carries no machine and no path at all,
# which is what `backend.nix` renders beside this file.
#
# Like the image realiser's reading, these refusals raise rather than becoming
# rows. A configuration assembled around a fact nobody wrote would store one
# instance's secret under another's name, so every refusal here names both sides.
{ planner }:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    elemAt
    filter
    genList
    groupBy
    head
    isString
    length
    listToAttrs
    match
    ;
  inherit (planner.util)
    mapAttrsToList
    quote
    quoteList
    sortStrings
    ;

  fail = message: throw "planner secrets: ${message}";

  # The character the projection joins on. `safe-name` admits it, which is what
  # makes a colon-joined name a name, and is also why a component carrying one
  # cannot be told apart from a joint.
  separator = ":";

  # `safe-name` is `^[a-zA-Z0-9:_\.-]+$` at revision
  # e6af758a5745ac4adef763deb0f1771cec58c461. A projected component is that
  # without the separator; a file name is not projected, so it keeps the colon.
  componentRule = "[a-zA-Z0-9_.-]+";
  fileRule = "[a-zA-Z0-9:_.-]+";
  admits = quoteList [
    "_"
    "."
    "-"
  ];

  # The name the tool keeps for its own provenance record.
  reservedFile = ".nixos-secrets-metadata";

  # Greedy on the instance: a plan key holds one colon before the marker, and a
  # key holding two is a key two components could be read out of, which is what
  # the collision check is here to catch rather than to read one way.
  keyRule = "(.+):vars/(.+)";

  required =
    key: entry: field:
    if entry ? ${field} then
      entry.${field}
    else
      fail "entry ${quote key} records no ${quote field}, and nothing else the plan carries says what it would be";

  # A per-placement value's key ends in `@<machine>`, so the machine is what
  # follows the last `@`. A generator whose own name carries one is refused by the
  # component rule rather than silently re-split.
  parseKey =
    plan: key:
    let
      m = match keyRule key;
      entry = plan.${key} or (fail "the plan carries no entry ${quote key}");
      rest = elemAt m 1;
      pieces = filter isString (builtins.split "@" rest);
      count = length pieces;
      perMachine = required key entry "per" == "placement" && count > 1;
    in
    if m == null then
      fail "${quote key} is not a generated value's key of the form `<instance>:vars/<generator>` or `<instance>:vars/<generator>@<machine>`"
    else
      {
        inherit key entry;
        instance = elemAt m 0;
        generator =
          if perMachine then concatStringsSep "@" (genList (i: elemAt pieces i) (count - 1)) else rest;
        machine = if perMachine then elemAt pieces (count - 1) else null;
      };

  component =
    role: parts: value:
    if match ".*${separator}.*" value != null then
      fail "the ${role} of ${quote parts.key} is ${quote value}, which carries ${quote separator} - the character the projected name joins on, so its name could not be read back; rename the ${role}"
    else if match componentRule value == null then
      fail "the ${role} of ${quote parts.key} is ${quote value}, and a name the external generator admits carries ASCII letters, digits, ${admits} and nothing else; rename the ${role}"
    else
      value;

  # <instance>:<generator>, or <instance>:<generator>:<machine> for a per-machine
  # value, so two machines' values of one generator stay two stored values.
  # Deliberately not a hash of the key: this name is what an operator reads in the
  # tool's own listing and in a prompt about deleting something.
  #
  # The join runs before the components are checked, so two keys landing on one
  # name are named as the pair they are rather than one at a time.
  joined =
    parts:
    concatStringsSep separator (
      [
        parts.instance
        parts.generator
      ]
      ++ (if parts.machine == null then [ ] else [ parts.machine ])
    );

  projected =
    parts:
    concatStringsSep separator (
      [
        (component "instance" parts parts.instance)
        (component "generator" parts parts.generator)
      ]
      ++ (if parts.machine == null then [ ] else [ (component "machine" parts parts.machine) ])
    );

  fileName =
    parts: name:
    if name == reservedFile then
      fail "generated file ${quote name} of ${quote parts.key} carries the name the external generator keeps for its own provenance record; rename the file"
    else if match fileRule name == null then
      fail "generated file ${quote name} of ${quote parts.key} is not a name the external generator admits, which carries ASCII letters, digits, ${separator}, ${admits} and nothing else; rename the file"
    else
      name;

  parsedOf =
    plan: map (parseKey plan) (sortStrings (filter (key: match keyRule key != null) (attrNames plan)));

  # The pairs a plan would store over one another, as a value rather than a
  # refusal, so what the refusal is about can be read without catching it.
  collisionsOf =
    plan:
    let
      byName = groupBy joined (parsedOf plan);
    in
    map (name: {
      inherit name;
      keys = map (parts: parts.key) byName.${name};
    }) (filter (name: length byName.${name} > 1) (sortStrings (attrNames byName)));

  valuesOf =
    plan:
    let
      collided = collisionsOf plan;
      first = head collided;
    in
    if collided != [ ] then
      fail "${quoteList first.keys} project onto one name, ${quote first.name}, and one would overwrite the other's stored bytes; rename one of the two"
    else
      map (parts: parts // { name = projected parts; }) (parsedOf plan);

  nameOf = plan: key: projected (parseKey plan key);

  storeEntry =
    plan: backend: value:
    let
      inherit (value) key entry;
      program =
        if entry ? program then
          entry.program
        else
          fail "entry ${quote key} records no ${quote "program"}, and the external generator runs one program per stored value; declare ${quote "program"} on the generator, or read this plan with something that needs none";
      deploy = required key entry "deploy";
      files = required key entry "files";
    in
    {
      inherit backend;
      generate = program;
      dependencies = sortStrings (map (nameOf plan) (entry.reads or [ ]));
      # The library has no prompt vocabulary, so nothing it plans can ask a
      # question, and a prompt asked at all is a defect rather than a value.
      prompts = { };
      # A value nobody receives is generated and stored and sent nowhere, which is
      # what `deploy = false` on every one of its files says.
      files = listToAttrs (
        mapAttrsToList (fname: _: {
          name = fileName value fname;
          value = {
            inherit deploy;
          };
        }) files
      );
    };

  storeOf =
    plan: backend:
    listToAttrs (
      map (value: {
        inherit (value) name;
        value = storeEntry plan backend value;
      }) (valuesOf plan)
    );

  addressOf =
    plan: value: machine:
    let
      record = plan."machine:${machine}" or null;
    in
    if record == null then
      fail "value ${quote value.key} is delivered to machine ${quote machine}, and the plan carries no ${quote "machine:${machine}"} entry to read an address out of"
    else if !(record ? address) || !isString record.address then
      fail "value ${quote value.key} is delivered to machine ${quote machine}, and that machine's entry records no address: the address is what is missing, and it is declared in the machine registry"
    else
      record.address;

  # The delivery set of every deployed value, with the address the plan records
  # for each machine and the path the plan fixed for each file. The contract
  # carries neither, so this is the whole machine dimension of the composition.
  deliveriesOf =
    plan:
    map (value: {
      inherit (value) key name;
      files = mapAttrsToList (fname: file: {
        file = fileName value fname;
        path = required "${value.key}, file ${quote fname} of it," file "path";
      }) (required value.key value.entry "files");
      machines = map (machine: {
        inherit machine;
        address = addressOf plan value machine;
      }) (required value.key value.entry "delivery");
    }) (filter (value: required value.key value.entry "deploy") (valuesOf plan));
in
{
  inherit
    valuesOf
    collisionsOf
    deliveriesOf
    nameOf
    ;

  # One store entry per generated value, keyed by its projected name. An entry of
  # the plan that is not a generated value contributes none.
  store =
    {
      plan,
      backend,
    }:
    storeOf plan backend;

  # `backends` is the caller's and not the plan's: where bytes live is a fact
  # about disk, which the library cannot see and gains no field for. `_type` is
  # what makes the object final, so the tool evaluates no Nix of ours.
  configuration =
    {
      plan,
      backend,
      backends,
    }:
    {
      _type = "secrets-configuration";
      inherit backends;
      store = storeOf plan backend;
    };
}
