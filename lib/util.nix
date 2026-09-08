# Builtins-only helpers. The library depends on korora and on nothing else, so
# the handful of list and attrset functions nixpkgs lib would have supplied are
# here instead.
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

  # Nix's store hash alphabet: base 32 without `e`, `o`, `t` and `u`.
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

  # A membership index over strings. Crossing one fleet-sized list against
  # another with `elem` is a scan per element; crossing it against this is a
  # lookup. An attribute name carries no context, so a store path is indexed by
  # its text, exactly as `uniqueStrings` keys it.
  stringSet =
    xs:
    listToAttrs (
      map (x: {
        name = builtins.unsafeDiscardStringContext x;
        value = true;
      }) xs
    );

  inStringSet = set: x: set ? ${builtins.unsafeDiscardStringContext x};

  # Deduplication over strings goes through an attribute set rather than a fold
  # with `++`, which would allocate a list per element and cost the square of
  # the fleet in a set-valued read. The result is sorted, which every caller
  # wanted anyway.
  #
  # An attribute name carries no context, so the set is keyed by the text and
  # the value is the string that was handed in. A closure root that came from a
  # package evaluated beside the plan keeps its context, which is what makes a
  # consumer of the plan able to copy the bytes; dropping it here would leave
  # every such root a path nothing had built.
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

  # Keys of `set` that are not in `allowed`.
  extraKeys = allowed: set: attrNames (removeAttrs set allowed);

  # The values of `set` at the names `allowed` carries, and no others. An
  # allow-list read: a name the set gained is absent until this list names it.
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

  # A literal string as a POSIX extended regular expression, so a store
  # directory carrying a regex metacharacter is matched as itself.
  escapeRegex = replaceStrings regexMeta (map (c: "\\${c}") regexMeta);

  # Every store root mentioned in a string, without the path inside it: the
  # closure is the store root a value points at.
  #
  # The hash is Nix's own: 32 characters over a base-32 alphabet that excludes
  # `e`, `o`, `t` and `u`, so 32 characters of a package name are not a hash.
  storePathsIn =
    storeDir:
    let
      pattern = "(${escapeRegex storeDir}/[${storeHashAlphabet}]{32}-[0-9a-zA-Z?=_.+-]+)";
    in
    value: if !isString value then [ ] else map head (filter isList (split pattern value));

  # Store roots mentioned anywhere in a plain data structure. The pattern is
  # built once per store directory rather than once per string, so an entry
  # whose strings number in the hundreds escapes the directory once.
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

  # A short content hash. Truncated because a plan is read by people; 64 bits is
  # still a hash of the whole input rather than a label.
  #
  # The context is discarded because a key is a hash of the text a plan holds,
  # and a store path in a plan may have arrived from a package evaluated in the
  # same evaluation. `hashString` refuses such a string, and the alternative -
  # keys that exist only for hand-written paths - would make the plan of a real
  # deployment unkeyable. Discarding here realises nothing: the string is
  # hashed, not built.
  shortHash =
    value: "sha256-${substring 0 16 (hashString "sha256" (builtins.unsafeDiscardStringContext value))}";

  # Nix has no printf, and a row that renders a count reads better in words for
  # the small numbers a slot arity produces.
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

  # A count and its noun agreeing, because a row reading "names one entries"
  # is a row a reader stops trusting.
  countNoun =
    n: noun: plural:
    "${countWord n} ${if n == 1 then noun else plural}";

  # Strip directories from a path-shaped string. Used to make a subject that
  # cannot differ between checkouts.
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

  # One line, so a row's message cannot smuggle a paragraph into a table.
  oneLine = s: replaceStrings [ "\n" ] [ " " ] s;
}
