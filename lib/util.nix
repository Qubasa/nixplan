# Builtins only. This library depends on korora and on nothing else, so the few
# list and attrset helpers nixpkgs lib would have supplied live here instead.
let
  inherit (builtins)
    attrNames
    concatLists
    concatStringsSep
    elem
    elemAt
    filter
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
