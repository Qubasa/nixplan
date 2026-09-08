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

  sortStrings = sort (a: b: a < b);

  subtractList = xs: ys: filter (x: !elem x ys) xs;

  stringSet =
    xs:
    listToAttrs (
      map (x: {
        name = builtins.unsafeDiscardStringContext x;
        value = true;
      }) xs
    );

  inStringSet = set: x: set ? ${builtins.unsafeDiscardStringContext x};

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

  isVarsFile = value: isAttrs value && (value.__varsFile or false);

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
