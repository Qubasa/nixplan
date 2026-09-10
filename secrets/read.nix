# Reading one plan as a configuration for the external secret generator.
#
# The generator's contract is a JSON object it consumes without evaluating any of
# this library's Nix: one store entry per generated value, a restricted name per
# entry, and one program per entry. It carries no machine and no path at all,
# which is what `backend.nix` renders beside this file.
#
# The reading has two halves and one statement per condition. `rows` answers what
# a plan would be refused for and raises nothing, and `store`, `configuration`
# and `deliveriesOf` refuse with the sentence that row states. `accounts` is what
# pairs the two, and `tests/unit/diagnostics.nix` fails the suite for a refusal
# whose account names no row a producing layer produces.
{ planner }:
let
  inherit (builtins)
    attrNames
    concatLists
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
    optional
    quote
    quoteList
    sortStrings
    ;

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

  # A path and an address are rendered into single-quoted words of the deploy
  # step, so one carrying a quote would be one that closes it. The rule lives
  # here rather than beside the rendering because the rows half reports it and
  # `backend.nix` is what imports this file.
  wordRule = "[a-zA-Z0-9_./:@%+=,~-]+";
  wordAdmits = quoteList [
    "_"
    "."
    "/"
    ":"
    "@"
    "%"
    "+"
    "="
    ","
    "~"
    "-"
  ];

  # The name the tool keeps for its own provenance record.
  reservedFile = ".nixos-secrets-metadata";

  # Greedy on the instance: a plan key holds one colon before the marker, and a
  # key holding two is a key two components could be read out of, which is what
  # the collision check is here to catch rather than to read one way.
  keyRule = "(.+):vars/(.+)";

  carriesSeparator = value: match ".*${separator}.*" value != null;
  outsideComponentRule = value: match componentRule value == null;
  outsideFileRule = name: match fileRule name == null;
  unrenderable = value: match wordRule value == null;

  # One statement per condition: `id` names the row that reports it, and `says`
  # is the sentence the row and the refusal both state, so the two cannot drift.
  # A condition no plan reaches carries `because` and no row.
  accounts = {
    keyNotAValue = {
      id = "secrets-key-not-a-value";
      says = key: {
        subject = key;
        message = "${quote key} is not a generated value's key of the form `<instance>:vars/<generator>` or `<instance>:vars/<generator>@<machine>`";
        evidence = "the reading stores one value per generated value entry, and a record of any other shape is read by something else";
        resolution = "declare the read against a generated value of this plan, or stop asking this reading for the stored name of ${quote key}";
      };
    };

    entryAbsent = {
      id = null;
      because = "the reading enumerates the plan, and the only other keys it looks up are the reads a value entry records, which the planner writes as keys of the same plan";
      says = key: {
        subject = key;
        message = "the plan carries no entry ${quote key}";
        evidence = "the reading enumerates the plan and looks up nothing but the reads a value entry recorded";
        resolution = "plan this deployment again, so that every read names an entry the plan carries";
      };
    };

    fieldMissing = {
      id = "secrets-value-field-missing";
      says =
        {
          key,
          field,
          at ? "",
        }:
        {
          subject = key;
          message = "entry ${quote key} records no ${quote field}${at}, and nothing else the plan carries says what it would be";
          evidence = "the external contract needs the field to store or to deliver the value, and this reading invents no field a plan does not record";
          resolution = "record ${quote field} on ${quote key}${at} whether or not it carries anything, the way `delivery` and `files` are recorded";
        };
    };

    programMissing = {
      id = "secrets-value-no-program";
      says = key: {
        subject = key;
        message = "entry ${quote key} records no ${quote "program"}, and the external generator runs one program per stored value";
        evidence = "a program is recorded only where the generator declared one, so a plan written before the field existed carries none";
        resolution = "declare ${quote "program"} on the generator, or read this plan with something that needs none";
      };
    };

    nameCarriesSeparator = {
      id = "secrets-name-carries-separator";
      says =
        {
          key,
          role,
          value,
        }:
        {
          subject = key;
          message = "the ${role} of ${quote key} is ${quote value}, which carries ${quote separator} - the character the projected name joins on, so its name could not be read back";
          evidence = "the projected name joins the instance, the generator and the machine with ${quote separator}, so a component carrying one cannot be told from a joint";
          resolution = "rename the ${role}";
        };
    };

    nameOutsideGrammar = {
      id = "secrets-name-outside-grammar";
      says =
        {
          key,
          role,
          value,
        }:
        {
          subject = key;
          message = "the ${role} of ${quote key} is ${quote value}, and a name the external generator admits carries ASCII letters, digits, ${admits} and nothing else";
          evidence = "the projected name is what an operator reads in the tool's own listing and in a prompt about deleting something, so it is the contract's grammar and not a hash";
          resolution = "rename the ${role}";
        };
    };

    fileNameReserved = {
      id = "secrets-file-name-reserved";
      says =
        {
          key,
          name,
        }:
        {
          subject = key;
          message = "generated file ${quote name} of ${quote key} carries the name the external generator keeps for its own provenance record";
          evidence = "the tool writes that record beside the files of a stored value, so a file of the same name is a file it would overwrite";
          resolution = "rename the file";
        };
    };

    fileNameOutsideGrammar = {
      id = "secrets-file-name-outside-grammar";
      says =
        {
          key,
          name,
        }:
        {
          subject = key;
          message = "generated file ${quote name} of ${quote key} is not a name the external generator admits, which carries ASCII letters, digits, ${separator}, ${admits} and nothing else";
          evidence = "a file name is not projected, so it reaches the contract as the author wrote it";
          resolution = "rename the file";
        };
    };

    nameCollision = {
      id = "secrets-name-collision";
      says =
        {
          name,
          keys,
        }:
        {
          subject = head keys;
          message = "${quoteList keys} project onto one name, ${quote name}, and one would overwrite the other's stored bytes";
          evidence = "the projection is not injective, and the name is what the tool stores a value under";
          resolution = "rename one of the two";
        };
    };

    machineUnknown = {
      id = "secrets-delivery-machine-unknown";
      says =
        {
          key,
          machine,
        }:
        {
          subject = key;
          message = "value ${quote key} is delivered to machine ${quote machine}, and the plan carries no ${quote "machine:${machine}"} entry to read an address out of";
          evidence = "the rendered deploy step dials every machine of a delivery set, and the plan is the only place an address comes from";
          resolution = "declare ${quote machine} in the deployment's machine registry, or stop delivering ${quote key} to it";
        };
    };

    machineNoAddress = {
      id = "secrets-delivery-machine-no-address";
      says =
        {
          key,
          machine,
        }:
        {
          subject = key;
          message = "value ${quote key} is delivered to machine ${quote machine}, and that machine's entry records no address";
          evidence = "the rendered deploy step is the one build artifact that carries an address, which is why the same absence is an error here and a warning of a deployment build";
          resolution = "declare an `address` for ${quote machine} in the deployment's machine registry";
        };
    };

    wordUnrenderable = {
      id = "secrets-rendered-word-refused";
      says =
        {
          key,
          what,
          named,
          value,
        }:
        {
          subject = key;
          message = "${what} of ${quote named} is ${quote value}, which is not something this reading will render into a shell script";
          evidence = "a path and an address are rendered into single-quoted words of the deploy step, and one carrying a quote would be one that closes it";
          resolution = "write ${quote named} as one shell word of ASCII letters, digits, ${wordAdmits} and nothing else";
        };
    };

    pathNamesNoDirectory = {
      id = null;
      because = "every path a plan records is `/run/vars/<instance>/<generator>/<file>`, fixed by the planner from the value's own key, so a recorded path always names a directory";
      says =
        {
          key,
          path,
        }:
        {
          subject = key;
          message = "the path ${quote path} of ${quote key} names no directory, so there is nothing to create on the machine that receives it";
          evidence = "the rendered step creates the parent of a path before it writes the file";
          resolution = "record the file at an absolute path, the way the planner writes `/run/vars/<instance>/<generator>/<file>`";
        };
    };
  };

  rowOf = account: args: planner.error ({ inherit (account) id; } // account.says args);

  fail =
    account: args:
    let
      said = account.says args;
    in
    throw "planner secrets: ${said.message}; ${said.resolution}";

  requiredAt =
    key: at: entry: field:
    if entry ? ${field} then entry.${field} else fail accounts.fieldMissing { inherit key field at; };

  required =
    key: entry: field:
    requiredAt key "" entry field;

  # A per-placement value's key ends in `@<machine>`, so the machine is what
  # follows the last `@`. A generator whose own name carries one is refused by the
  # component rule rather than silently re-split.
  partsOf =
    plan: key:
    let
      m = match keyRule key;
      entry = plan.${key} or { };
      rest = elemAt m 1;
      pieces = filter isString (builtins.split "@" rest);
      count = length pieces;
      perMachine = (entry.per or null) == "placement" && count > 1;
    in
    {
      inherit key entry;
      instance = elemAt m 0;
      generator =
        if perMachine then concatStringsSep "@" (genList (i: elemAt pieces i) (count - 1)) else rest;
      machine = if perMachine then elemAt pieces (count - 1) else null;
    };

  parseKey =
    plan: key:
    if match keyRule key == null then
      fail accounts.keyNotAValue key
    else if !(plan ? ${key}) then
      fail accounts.entryAbsent key
    else if !(plan.${key} ? per) then
      fail accounts.fieldMissing {
        inherit key;
        field = "per";
      }
    else
      partsOf plan key;

  component =
    role: parts: value:
    if carriesSeparator value then
      fail accounts.nameCarriesSeparator {
        inherit (parts) key;
        inherit role value;
      }
    else if outsideComponentRule value then
      fail accounts.nameOutsideGrammar {
        inherit (parts) key;
        inherit role value;
      }
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
      fail accounts.fileNameReserved {
        inherit (parts) key;
        inherit name;
      }
    else if outsideFileRule name then
      fail accounts.fileNameOutsideGrammar {
        inherit (parts) key;
        inherit name;
      }
    else
      name;

  keysOf = plan: sortStrings (filter (key: match keyRule key != null) (attrNames plan));

  parsedOf = plan: map (parseKey plan) (keysOf plan);

  # The pairs a plan would store over one another, as a value rather than a
  # refusal, so what the refusal is about can be read without catching it.
  collisionsOf =
    plan:
    let
      byName = groupBy joined (map (partsOf plan) (keysOf plan));
    in
    map (name: {
      inherit name;
      keys = map (parts: parts.key) byName.${name};
    }) (filter (name: length byName.${name} > 1) (sortStrings (attrNames byName)));

  valuesOf =
    plan:
    let
      collided = collisionsOf plan;
    in
    if collided != [ ] then
      fail accounts.nameCollision (head collided)
    else
      map (parts: parts // { name = projected parts; }) (parsedOf plan);

  nameOf = plan: key: projected (parseKey plan key);

  storeEntry =
    plan: backend: value:
    let
      inherit (value) key entry;
      program = if entry ? program then entry.program else fail accounts.programMissing key;
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
      fail accounts.machineUnknown {
        inherit (value) key;
        inherit machine;
      }
    else if !(record ? address) || !isString record.address then
      fail accounts.machineNoAddress {
        inherit (value) key;
        inherit machine;
      }
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
        path = requiredAt value.key " on file ${quote fname}" file "path";
      }) (required value.key value.entry "files");
      machines = map (machine: {
        inherit machine;
        address = addressOf plan value machine;
      }) (required value.key value.entry "delivery");
    }) (filter (value: required value.key value.entry "deploy") (valuesOf plan));

  # The other half, over the same predicates and the same descriptions: what a
  # caller reading this plan for a configuration would be refused with, as rows.
  valueRowsOf =
    plan: user: key:
    let
      entry = plan.${key};
      parts = partsOf plan key;
      deployed = entry.deploy or false;
      delivery = if deployed then entry.delivery or [ ] else [ ];

      componentRows =
        role: value:
        if carriesSeparator value then
          [
            (rowOf accounts.nameCarriesSeparator { inherit key role value; })
          ]
        else
          optional (outsideComponentRule value) (
            rowOf accounts.nameOutsideGrammar { inherit key role value; }
          );

      fileRowsOf =
        name: file:
        (
          if name == reservedFile then
            [ (rowOf accounts.fileNameReserved { inherit key name; }) ]
          else
            optional (outsideFileRule name) (rowOf accounts.fileNameOutsideGrammar { inherit key name; })
        )
        ++ (
          if !deployed then
            [ ]
          else if !(file ? path) then
            [
              (rowOf accounts.fieldMissing {
                inherit key;
                field = "path";
                at = " on file ${quote name}";
              })
            ]
          else
            optional (delivery != [ ] && unrenderable file.path) (
              rowOf accounts.wordUnrenderable {
                inherit key;
                what = "the path";
                named = key;
                value = file.path;
              }
            )
        );

      machineRowsOf =
        machine:
        let
          record = plan."machine:${machine}" or null;
        in
        if record == null then
          [ (rowOf accounts.machineUnknown { inherit key machine; }) ]
        else if !(record ? address) || !isString record.address then
          [ (rowOf accounts.machineNoAddress { inherit key machine; }) ]
        else
          optional (unrenderable "${user}@${record.address}") (
            rowOf accounts.wordUnrenderable {
              inherit key;
              what = "the address";
              named = machine;
              value = "${user}@${record.address}";
            }
          );
    in
    map (field: rowOf accounts.fieldMissing { inherit key field; }) (
      filter (field: !(entry ? ${field})) (
        [
          "per"
          "deploy"
          "files"
        ]
        ++ optional deployed "delivery"
      )
    )
    ++ optional (!(entry ? program)) (rowOf accounts.programMissing key)
    ++ componentRows "instance" parts.instance
    ++ componentRows "generator" parts.generator
    ++ (if parts.machine == null then [ ] else componentRows "machine" parts.machine)
    ++ concatLists (mapAttrsToList fileRowsOf (entry.files or { }))
    ++ concatLists (map machineRowsOf delivery)
    ++ concatLists (
      map (read: optional (match keyRule read == null) (rowOf accounts.keyNotAValue read)) (
        entry.reads or [ ]
      )
    );

  rowsOf =
    plan: user:
    concatLists (map (valueRowsOf plan user) (keysOf plan))
    ++ map (collision: rowOf accounts.nameCollision collision) (collisionsOf plan);
in
{
  inherit
    valuesOf
    collisionsOf
    deliveriesOf
    nameOf
    accounts
    ;

  # `backend.nix` renders what the contract's deploy step cannot carry, so the
  # rule it holds an address and a path to is this file's and so is the refusal
  # it states: one condition, one description, one account.
  inherit unrenderable fail;

  # What this plan would be refused for, as rows and without raising. `user` is
  # the account the rendered step dials with, because the word it renders is
  # `<user>@<address>` and the rule is about that word.
  rows =
    {
      plan,
      user ? "root",
    }:
    rowsOf plan user;

  # The plan's own table and this reading's, as one. A build over this refuses
  # with the rendered table rather than with a sentence of its own, so an
  # operator reads one table whichever half produced the row.
  generation =
    {
      plan,
      diagnostics ? [ ],
      user ? "root",
    }:
    let
      table = planner.mkTable (diagnostics ++ rowsOf plan user);
      refused = filter (r: r.severity == "error") table != [ ];
    in
    {
      inherit refused;
      diagnostics = table;
      refusal =
        if refused then
          "planner secrets: this plan cannot be read as a generator configuration.\n\n" + planner.render table
        else
          null;
    };

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
