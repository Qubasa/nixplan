# Builtins only. This library depends on korora and on nothing else, so the few
# list and attrset helpers nixpkgs lib would have supplied live here instead.
let
  inherit (builtins)
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
    isList
    isString
    length
    listToAttrs
    match
    replaceStrings
    sort
    split
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

  concatMapAttrsToList = f: set: concatLists (mapAttrsToList f set);

  filterAttrs =
    pred: set:
    listToAttrs (
      map (n: {
        name = n;
        value = set.${n};
      }) (filter (n: pred n set.${n}) (attrNames set))
    );

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

  # The grammar of one word a rendered shell step can carry. A path and an
  # address are rendered into single-quoted words, so one carrying a quote would
  # be one that closes it. Two steps of this repository render such a word, the
  # secrets delivery and the image attach script, so the rule has one home here
  # and neither reading states it again.
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

  unrenderable = value: match wordRule value == null;

  sortStrings = sort (a: b: a < b);

  subtractList = xs: ys: filter (x: !elem x ys) xs;

  # A membership index. Crossing two fleet-sized lists with elem is a scan per
  # element, against this it is a lookup.
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

  storePathsDeep =
    storeDir:
    let
      scan = storePathsIn storeDir;
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

  # Which of `needles` a value mentions anywhere inside it. The same traversal as
  # storePathsDeep, for paths that are not store paths and have no grammar of
  # their own: a generated file's path is whatever the planner fixed it to.
  mentionsDeep =
    needles:
    let
      deep =
        value:
        if isString value then
          filter (needle: match ".*${escapeRegex needle}.*" value != null) needles
        else if isList value then
          concatLists (map deep value)
        else if isAttrs value then
          concatLists (mapAttrsToList (_: deep) value)
        else
          [ ];
    in
    deep;

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

  isVarsFile = value: isAttrs value && (value.__varsFile or false);

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

  oneLine = s: replaceStrings [ "\n" ] [ " " ] s;
}
