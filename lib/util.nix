# Builtins only. This library depends on korora and on nothing else, so the few
# list and attrset helpers nixpkgs lib would have supplied live here instead.
let
  inherit (builtins)
    all
    any
    attrNames
    concatLists
    concatStringsSep
    elem
    elemAt
    filter
    genList
    hashString
    head
    isAttrs
    isFunction
    isList
    isString
    length
    listToAttrs
    match
    replaceStrings
    sort
    split
    stringLength
    substring
    ;

  regexMeta = [
    "\\"
    "."
    "["
    "]"
    "("
    ")"
    "{"
    "}"
    "*"
    "+"
    "?"
    "^"
    "$"
    "|"
  ];

  # Nix's store hash alphabet: base 32 without e, o, t and u.
  storeHashAlphabet = "0123456789abcdfghijklmnpqrsvwxyz";
in
rec {
  mapAttrsToList = f: set: map (n: f n set.${n}) (attrNames set);

  # The walk written out rather than composed over mapAttrsToList, which would
  # cost two applications per call on top of the one per attribute.
  concatMapAttrsToList = f: set: concatLists (map (n: f n set.${n}) (attrNames set));

  genAttrs =
    names: f:
    listToAttrs (
      map (n: {
        name = n;
        value = f n;
      }) names
    );

  # A list keyed by a pair the caller writes. One application per element, which
  # is what the walk written out costs, so a reading inside this library builds
  # its index through this and pays for no projection it did not need.
  mapToAttrs = f: xs: listToAttrs (map f xs);

  # The same walk with the key and the value as two projections, which is what a
  # realiser indexing a rendered list wants and what costs two applications per
  # element.
  indexBy =
    key: value:
    mapToAttrs (x: {
      name = key x;
      value = value x;
    });

  # removeAttrs is one primop over the whole set, where rebuilding it through
  # listToAttrs allocates a thunk and an attribute per name that survives.
  filterAttrs = pred: set: removeAttrs set (filter (n: !(pred n set.${n})) (attrNames set));

  # The instances-by-members nesting, flat. Every reading over a resolved
  # deployment walks it, so it has one spelling and a reading states what it does
  # with a member rather than how the two levels are reached. The callback is
  # applied one argument at a time, so a member costs the two applications the
  # nesting itself costs and never a third.
  eachMember =
    resolved: f:
    concatMapAttrsToList (iname: inst: concatMapAttrsToList (f iname) inst.members) resolved.instances;

  optional = cond: value: if cond then [ value ] else [ ];

  # Order-preserving, by value equality. `uniqueStrings` is the keyed form for
  # strings; this is the one for values a key cannot be built from.
  distinct =
    values:
    builtins.foldl' (
      seen: value: if builtins.any (v: v == value) seen then seen else seen ++ [ value ]
    ) [ ] values;

  # The characters a plan key's own structure spends. A key is
  # `<instance>:<member>@<machine>` and a generated value's is
  # `<instance>:vars/<generator>@<machine>`, read by taking the first `:`, the
  # last `@` and the `vars/` prefix, so a name carrying one of them produces a
  # key that takes apart into parts nothing declared - or, for `/`, a service
  # entry whose key is a value entry's. The rule is these three rather than an
  # allowlist, which would refuse names existing deployments legitimately use.
  keySeparators = [
    "/"
    "@"
    ":"
  ];

  carriesKeySeparator = name: isString name && match ".*[@:/].*" name != null;

  # The whole grammar a name entering a key is held to: the three separators
  # above, and the two more a key built from them can be neither recovered from
  # nor rendered. The empty name recovers as nothing, and a control character
  # reaches a rendered table and a unit file name as a line of its own.
  unkeyableName =
    name:
    !(isString name) || name == "" || carriesKeySeparator name || match ".*[[:cntrl:]].*" name != null;

  nameAdmits = "a non-empty name of no control character and none of ${quoteList keySeparators}";

  # The grammar of one word a rendered shell step can carry. A path and an
  # address are rendered into single-quoted words, so one carrying a quote would
  # be one that closes it. Two steps of this repository render such a word, the
  # secrets delivery and the image attach script, so the rule has one home here
  # and neither reading states it again.
  wordExtras = [
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

  # The two a service manager reads as its own inside the value of a bind: `:`
  # separates one bind from the next, and `%` introduces a specifier it expands
  # before the bind is made. A host path reaches a bind as well as a shell word,
  # so its grammar is the word grammar without them.
  bindReserved = [
    ":"
    "%"
  ];

  pathExtras = subtractList wordExtras bindReserved;

  characterClass = extras: "[a-zA-Z0-9${concatStringsSep "" extras}]+";

  wordRule = characterClass wordExtras;
  wordAdmits = quoteList wordExtras;

  pathRule = characterClass pathExtras;
  pathAdmits = quoteList pathExtras;

  # One age native X25519 recipient: the public line `age-keygen` prints beside
  # the identity file it writes. The class is a *subset* of `wordRule`'s - the
  # bech32 alphabet is lowercase letters and digits, and `age1` is alphanumeric
  # - which is what lets a rendered deploy step carry a recipient as an ordinary
  # word instead of a file in the store. An SSH recipient line, which the first
  # draft sealed to, carries spaces and could not.
  bech32Alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

  ageRecipientRule = "age1[${bech32Alphabet}]{58}";
  ageRecipientAdmits = "${quote "age1"} followed by 58 characters of the bech32 alphabet ${quote bech32Alphabet}";

  unrenderable = value: match wordRule value == null;

  unbindable = value: match pathRule value == null;

  # The grammar a service manager carries for an environment variable's name. An
  # assignment is written `NAME=value`, so a name outside this is a directive the
  # manager refuses in part and a unit that starts without the variable.
  envNameRule = "[a-zA-Z_][a-zA-Z0-9_]*";
  envNameAdmits = "a letter or an underscore followed by letters, digits and underscores";

  unassignable = name: !(isString name) || match envNameRule name == null;

  # The escape the two rendered steps spend beside the grammar above. Always
  # quoted, because a bare safe-looking word is what `lib.escapeShellArg` leaves
  # behind and a value no rule has reached yet still has to survive one shell.
  shellQuote = value: "'${replaceStrings [ "'" ] [ "'\\''" ] value}'";

  # Whether a function accepts the argument record a caller is about to hand it.
  # A closed attribute pattern refuses a key it does not name and a formal with
  # no default it is not given, and the interpreter lets a caller catch neither,
  # so the pattern is read before the application rather than recovered from
  # after it. `builtins.toXML` of a function prints its pattern and never its
  # body, and is the one place the ellipsis is observable: `functionArgs`
  # answers the same record for `{ a }` and for `{ a, ... }`.
  formalsRefused =
    f: record:
    let
      pattern = builtins.toXML f;
      formals = builtins.functionArgs f;
      closed = match ".*<attrspat.*" pattern != null && match ".*ellipsis=\"1\".*" pattern == null;
    in
    if !closed then
      {
        extra = [ ];
        missing = [ ];
      }
    else
      {
        extra = subtractList (attrNames record) (attrNames formals);
        missing = filter (n: !formals.${n} && !(record ? ${n})) (attrNames formals);
      };

  sortStrings = sort (a: b: a < b);

  subtractList = xs: ys: filter (x: !elem x ys) xs;

  # A membership index. Crossing two fleet-sized lists with elem is a scan per
  # element, against this it is a lookup. The walk is written out rather than
  # taken through mapToAttrs, which would cost an application per call on a
  # question asked once per unit of every entry.
  stringSet =
    xs:
    listToAttrs (
      map (x: {
        name = builtins.unsafeDiscardStringContext x;
        value = true;
      }) xs
    );

  inStringSet = set: x: set ? ${builtins.unsafeDiscardStringContext x};

  # Deduplication through an attribute set rather than a fold, which would cost the
  # square of the fleet. The value keeps the string that was handed in, so a
  # closure root evaluated beside the plan keeps its context and a consumer can
  # still copy the bytes.
  uniqueStrings =
    xs:
    let
      index = listToAttrs (
        map (x: {
          name = builtins.unsafeDiscardStringContext x;
          value = x;
        }) xs
      );
    in
    map (n: index.${n}) (attrNames index);

  extraKeys = allowed: set: attrNames (removeAttrs set allowed);

  pickAttrs =
    allowed: set:
    listToAttrs (
      map (n: {
        name = n;
        value = set.${n};
      }) (filter (n: set ? ${n}) allowed)
    );

  quote = s: "`${s}`";

  quoteList = xs: if xs == [ ] then "none" else concatStringsSep ", " (map quote xs);

  # How a row shows a value whose kind is the mistake. A string is quoted and any
  # other value is named by its type, so no row interpolates bytes a caller wrote
  # into a sentence about their shape.
  shownValue = v: if isString v then quote v else "a value of type ${builtins.typeOf v}";

  joinLines = concatStringsSep "\n";

  escapeRegex = replaceStrings regexMeta (map (c: "\\${c}") regexMeta);

  # Every store root a string mentions, without the path inside it. The hash is 32
  # characters of the alphabet above, so 32 characters of a package name are not
  # mistaken for one.
  storePathsIn =
    storeDir:
    let
      pattern = "(${escapeRegex storeDir}/[${storeHashAlphabet}]{32}-[0-9a-zA-Z?=_.+-]+)";
    in
    value: if !isString value then [ ] else map head (filter isList (split pattern value));

  # Whether a string names a path inside the store: exactly one store root, at
  # the front of it. A configuration file's `source` is a path inside a store
  # object rather than the object itself, so this is not the rule a generator's
  # `program` is held to.
  inStore =
    storeDir:
    let
      scan = storePathsIn storeDir;
    in
    value:
    isString value
    && (
      let
        roots = scan value;
      in
      length roots == 1 && substring 0 (stringLength (head roots)) value == head roots
    );

  # Whether a value carries a function anywhere inside it, which is what makes
  # it unserialisable: `toJSON` of one is a coercion no recovery catches, and a
  # settings knob is serialised into an entry's key. The walk stops at a record
  # carrying `outPath`, which is what `toJSON` itself serialises by that string.
  carriesFunction =
    value:
    if isFunction value then
      true
    else if isList value then
      any carriesFunction value
    else if isAttrs value then
      !(value ? outPath) && any (name: carriesFunction value.${name}) (attrNames value)
    else
      false;

  # One traversal per per-string scan: a list is its elements, a record is its
  # values, and a value of any other kind names nothing.
  deepScan =
    scan:
    let
      deep =
        value:
        if isString value then
          scan value
        else if isList value then
          concatLists (map deep value)
        else if isAttrs value then
          concatLists (mapAttrsToList (_: deep) value)
        else
          [ ];
    in
    deep;

  storePathsDeep = storeDir: deepScan (storePathsIn storeDir);

  # Where a generated value lands on a machine. One home, because the reading
  # that builds the path and the scan that recognises one have to agree about
  # its shape.
  varsRoot = "/run/vars";

  # Where a copy of a delivered value is kept so the machine can put the value
  # back by itself after a reboot. Beside `varsRoot` and deliberately outside
  # it, for two reasons a reader has to see together: a service manager clears
  # `/run` across a reboot and clears nothing here, and `varsPathsIn` below
  # recognises a value's path by its shape *under `varsRoot`*, so a copy inside
  # that root would be read as a mention of a value no module declared. Nothing
  # in this library spends either of the two below per entry: they are the
  # definitions a realiser and the command spend.
  sealedRoot = "/var/lib/planner/sealed";

  # A file's sealed path from its runtime path: the root replaced and the
  # extension age publishes for its own files appended, so a sealed path is
  # derived from the value's identity - the instance, the generator and the file
  # name - exactly as far as the runtime path is, and no deployment states one.
  sealedPathOf =
    path: "${sealedRoot}${substring (stringLength varsRoot) (stringLength path) path}.age";

  # Every generated value path a string names: the root, the instance, the
  # generator and the file. Read by its shape and never by comparison against
  # the paths the plan carries, because a fleet makes both lists fleet-sized and
  # a comparison is then a scan per value per string. What a caller does with a
  # token is look it up, so a path this misreads names no value and is no row.
  varsPathsIn =
    let
      component = "[^/[:space:]\"]+";
      pattern = "(${escapeRegex varsRoot}/${component}/${component}/${component})";
    in
    value: if !isString value then [ ] else map head (filter isList (split pattern value));

  # The same traversal storePathsDeep does, for those paths.
  varsPathsDeep = deepScan varsPathsIn;

  # Every string a value carries at any depth, beside the field path it sits at.
  # storePathsDeep's traversal, keeping the path so a caller can name the field
  # rather than the record, and iterating the value rather than a list of fields
  # so a field added anywhere inside it is covered by existing. An attribute name
  # is one of those strings: it reaches a line-oriented file the way its value
  # does, so it is emitted at the same path the value is. The path stays a thunk
  # nothing on a clean walk forces.
  stringsDeep =
    let
      deep =
        path: value:
        if isString value then
          [
            {
              inherit path value;
            }
          ]
        else if isList value then
          concatLists (genList (i: deep "${path}[${toString i}]" (elemAt value i)) (length value))
        else if isAttrs value then
          concatLists (
            mapAttrsToList (
              name: attr:
              let
                at = if path == "" then name else "${path}.${name}";
              in
              [
                {
                  path = at;
                  value = name;
                }
              ]
              ++ deep at attr
            ) value
          )
        else
          [ ];
    in
    deep "";

  # A line-oriented file cannot carry a line break inside a value. A space, a
  # quote and a backslash it can: those are escaped where the value is rendered.
  # One list serves the scan and the repair below it, so a character the scan
  # counts cannot survive the repair.
  lineBreaks = [
    "\n"
    "\r"
  ];

  carriesLineBreak = value: isString value && match ".*[\n\r].*" value != null;

  # The same question with no bookkeeping, so a caller gates stringsDeep on it and
  # pays for a field path only where there is a row to name one. It reads each
  # attribute's name beside its value in one pass over the names, because the walk
  # it gates reports a name too and a gate that missed one would answer no for a
  # record stringsDeep has a row about.
  anyLineBreak =
    value:
    if isString value then
      carriesLineBreak value
    else if isList value then
      any anyLineBreak value
    else if isAttrs value then
      any (name: carriesLineBreak name || anyLineBreak value.${name}) (attrNames value)
    else
      false;

  # A read bit is the octal digit carrying 4.
  opensDigit =
    digit:
    elem digit [
      "4"
      "5"
      "6"
      "7"
    ];

  # A unit's declared groups are whatever its extension applications record under
  # `supplementaryGroups`, under any backend, so this names no realiser and the
  # key is the one a realiser's directive table and this rule both read.
  declaredGroups =
    unit:
    concatLists (
      map (
        fields:
        let
          declared = fields.supplementaryGroups or null;
        in
        if isList declared then
          filter isString declared
        else if isString declared then
          [ declared ]
        else
          [ ]
      ) (builtins.attrValues (unit.extends or { }))
    );

  # Whether a unit may open a file, from the file's recorded ownership and mode
  # and the unit's own account. One rule, asked wherever those facts are held.
  #
  # `rootAdmitted` is the single thing its callers differ on, so it is an argument
  # rather than a second copy of the comparison. The planner reads a unit running
  # unconfined as the account it declares, and one declaring none is root, so both
  # spellings of root open anything. A confining profile imposes the account and
  # never imposes root, so there an undeclared account owns nothing.
  #
  # The group clause asks about the unit's declared groups and not about its
  # account, so a unit naming a group and no account is admitted by that group
  # under either answer.
  admits =
    { rootAdmitted }:
    unit: file:
    let
      account = unit.user or null;
    in
    (rootAdmitted && (account == null || account == "root"))
    || (account != null && account == file.owner && opensDigit (substring 1 1 file.mode))
    || (elem file.group (declaredGroups unit) && opensDigit (substring 2 1 file.mode))
    || opensDigit (substring 3 1 file.mode);

  # A generated file reference, recognised by the record a caller indexes and not
  # by the marker alone: an export carrying the marker and nothing else would be
  # read as one and then indexed for fields it does not carry.
  varsFileKeys = [
    "__varsFile"
    "content"
    "deploy"
    "entry"
    "file"
    "generator"
    "group"
    "mode"
    "owner"
    "path"
    "present"
    "secrecy"
  ];

  isVarsFile =
    value: isAttrs value && (value.__varsFile or false) && all (k: value ? ${k}) varsFileKeys;

  # A short content hash, truncated because people read plans. The context is
  # discarded because hashString refuses a string that carries one, and a plan of a
  # real deployment has to stay keyable. Hashing realises nothing.
  shortHash =
    value: "sha256-${substring 0 16 (hashString "sha256" (builtins.unsafeDiscardStringContext value))}";

  countWord =
    n:
    let
      words = [
        "zero"
        "one"
        "two"
        "three"
        "four"
        "five"
        "six"
        "seven"
        "eight"
        "nine"
      ];
    in
    if n < length words then elemAt words n else toString n;

  countNoun =
    n: noun: plural:
    "${countWord n} ${if n == 1 then noun else plural}";

  baseNameOfString =
    s:
    let
      nonEmpty = filter (p: p != "") (filter isString (split "/" s));
    in
    if nonEmpty == [ ] then "unnamed" else elemAt nonEmpty (length nonEmpty - 1);

  isRelativePath =
    s:
    isString s
    && s != ""
    && match "/.*" s == null
    && match "\\.\\./.*" s == null
    && match ".*[[:space:]].*" s == null;

  oneLine = s: replaceStrings lineBreaks (map (_: " ") lineBreaks) s;
}
