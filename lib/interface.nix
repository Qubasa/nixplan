# Interfaces, export atoms and the typed extensions a backend adds to the unit
# vocabulary.
#
# An interface is the value an author imported. It is identified by that value or
# by an identity it claims with an `id`, never by a name resolved at composition
# time, it is validated against no registry, and its name is a label that appears
# in diagnostic output and nowhere else. Two interfaces in two files may carry one
# name, and a unit extension is the same construction under the same rule with no
# claim of its own: it is read from the value an author wrote into `extends` and
# is never matched against a far end.
{
  util,
  diag,
  excluded,
}:
let
  inherit (builtins)
    attrNames
    elem
    isAttrs
    isFunction
    isString
    match
    ;

  atomKeys = [
    "type"
    "secrecy"
  ];

  extensionFieldKeys = [ "type" ];

  applicationKeys = [
    "extension"
    "values"
  ];

  secrecies = [
    "public"
    "secret"
  ];

  isType = t: isAttrs t && t ? verify && isFunction t.verify;
in
rec {
  inherit secrecies;

  # The whole constructor. No registration and no side table: an interface nobody
  # upstreamed is an interface. A `fold` is the policy for combining the set a
  # set-valued read collects, and an `id` is a claim of identity two authors can
  # both write. Both are optional in every position.
  interface =
    {
      name,
      exports,
      fold ? null,
      id ? null,
    }:
    {
      inherit
        name
        exports
        fold
        id
        ;
    };

  foldOf = iface: iface.fold or null;

  # `typedef name verify` with the words changed: a function plus the only part of
  # it two evaluations can compare. A bare function stays a fold, so foldApply is
  # what a caller applies and foldName is what an identity carries.
  fold = name: apply: { inherit name apply; };

  isNamedFold = f: isAttrs f && f ? name && f ? apply;

  foldName = f: if isNamedFold f then f.name else null;

  foldApply = f: if isNamedFold f then f.apply else f;

  secrecyOf = atom: atom.secrecy or "public";

  exportNames = iface: attrNames iface.exports;

  secretExports =
    iface: builtins.filter (e: secrecyOf iface.exports.${e} == "secret") (exportNames iface);

  isName = s: isString s && match "[^[:space:]]+" s != null;

  # A claim carries no function at any depth, so two interfaces built by two
  # evaluations of this library compare by ordinary equality. A claim nobody made
  # and a claim the library refused are both null, and null is equal to no claim.
  identityOf =
    iface:
    let
      id = iface.id or null;
      declaredFold = foldOf iface;
      name = foldName declaredFold;
    in
    if !isInterface iface || !isName id || (declaredFold != null && !isName name) then
      null
    else
      {
        inherit id;
        exports = builtins.mapAttrs (_: atom: {
          type = if isType (atom.type or null) then atom.type.name or null else null;
          secrecy = secrecyOf atom;
        }) iface.exports;
        fold = name;
      };

  # An interface's declaring file, found by value in the registry the caller passed
  # to mkPlan and then by the identity it claims, so a row about an interface
  # another evaluation built can still print a file. A miss is not an error: the
  # registry exists so a row can print a file beside a name, not so an interface
  # can be rejected for being absent.
  registry =
    interfaces:
    util.concatMapAttrsToList (
      file: declared:
      util.mapAttrsToList (attr: value: {
        inherit file attr value;
      }) declared
    ) interfaces;

  fileOf =
    reg: iface:
    let
      hits = builtins.filter (r: r.value == iface) reg;
      claim = identityOf iface;
      claimed = if claim == null then [ ] else builtins.filter (r: identityOf r.value == claim) reg;
    in
    if hits != [ ] then
      (builtins.head hits).file
    else if claimed == [ ] then
      null
    else
      (builtins.head claimed).file;

  label =
    reg: iface:
    let
      file = fileOf reg iface;
    in
    if file == null then
      "${util.quote iface.name} (declaring file not recorded in the `interfaces` argument of mkPlan)"
    else
      "${util.quote iface.name} (${file})";

  subjectOf =
    reg: iface:
    let
      file = fileOf reg iface;
    in
    if file == null then "interface:${iface.name}" else file;

  typedFieldRows =
    {
      subject,
      what,
      carrier,
      shape,
      spelling,
      allowed,
      field,
      ids,
    }:
    map (
      key:
      if excluded.constructs ? ${key} then
        diag.error {
          inherit subject;
          id = ids.excluded;
          message = "${what} declares ${util.quote key}, which ${carrier} does not carry";
          evidence = "the condition that introduces it: ${excluded.constructs.${key}.trigger}";
          resolution = "delete ${util.quote key} from ${subject}, or land the change that adds the field before writing it";
        }
      else
        diag.error {
          inherit subject;
          id = ids.unknown;
          message = "${what} declares ${util.quote key}, and ${shape} declares ${util.quoteList allowed} and nothing else";
          evidence = "declared keys are ${util.quoteList (attrNames field)}";
          resolution = "delete ${util.quote key} from ${subject}";
        }
    ) (util.extraKeys allowed field)
    ++ util.optional (!(field ? type) || !isType field.type) (
      diag.error {
        inherit subject;
        id = ids.missingType;
        message = "${what} declares no type";
        evidence = "${spelling} and `type` must be a korora type";
        resolution = "give ${what} a type from the attribute set the planner hands ${subject}";
      }
    );

  atomRows =
    reg: iface:
    let
      subject = subjectOf reg iface;

      atomRowsFor =
        ename: atom:
        typedFieldRows {
          inherit subject;
          what = "export atom ${iface.name}.${ename}";
          carrier = "an export in this subset";
          shape = "an atom";
          spelling = "an atom is ${util.quote "{ type, secrecy ? \"public\" }"}";
          allowed = atomKeys;
          field = atom;
          ids = {
            excluded = "export-atom-excluded-key";
            unknown = "export-atom-unknown-key";
            missingType = "export-atom-missing-type";
          };
        }
        ++ util.optional (!elem (secrecyOf atom) secrecies) (
          diag.error {
            inherit subject;
            id = "export-atom-secrecy-domain";
            message = "export atom ${iface.name}.${ename} declares secrecy ${util.quote (toString (secrecyOf atom))}, and secrecy takes ${util.quoteList secrecies}";
            evidence = "an omitted secrecy means `public`";
            resolution = "write one of ${util.quoteList secrecies} in ${subject}, or omit the key";
          }
        );
    in
    util.concatMapAttrsToList atomRowsFor iface.exports;

  # A fold is applied to a value the planner built, so a declared fold that cannot
  # be applied is a row against the interface rather than an error at the read.
  foldApplicable =
    f: f != null && isFunction (foldApply f) && (!isNamedFold f || isName (foldName f));

  foldRows =
    reg: iface:
    let
      subject = subjectOf reg iface;
      declaredFold = foldOf iface;
      name = foldName declaredFold;
    in
    util.optional (declaredFold != null && !isFunction (foldApply declaredFold)) (
      diag.error {
        inherit subject;
        id = "interface-fold-not-a-function";
        message = "interface ${label reg iface} declares a fold that is not a function";
        evidence = "a fold is applied to the set a read collects, keyed by provider entry key, and returns the value the consuming implementation receives";
        resolution = "write ${util.quote "fold = set: …;"} in ${subject}, or delete the key";
      }
    )
    ++ util.optional (isNamedFold declaredFold && !isName name) (
      diag.error {
        inherit subject;
        id = "interface-fold-name-malformed";
        message = "interface ${label reg iface} names its fold ${writtenAs name}, and a fold's name is a non-empty string carrying no whitespace";
        evidence = "a fold's name is the only part of it two evaluations of this library can compare, so a name that is not one compares with nothing; the fold is not applied and a set-valued read delivers the set it collected";
        resolution = "write ${util.quote "fold = planner.fold \"<name>\" (set: …);"} in ${subject}, or declare the fold as a bare function";
      }
    );

  # A claim is refused rather than trusted, and a refused claim leaves the
  # interface identified by its value: one bad string is one row, not a cascade.
  writtenAs = v: if isString v then util.quote v else "a value of type ${builtins.typeOf v}";

  idRows =
    reg: iface:
    let
      subject = subjectOf reg iface;
      id = iface.id or null;
      declaredFold = foldOf iface;
    in
    util.optional (id != null && !isName id) (
      diag.error {
        inherit subject;
        id = "interface-id-malformed";
        message = "interface ${label reg iface} claims the identity ${writtenAs id}, and an identity is claimed with a non-empty string carrying no whitespace";
        evidence = "an identity is claimed with a string two authors can both write, so a claim that is not one identifies nothing; this interface is identified by its value instead";
        resolution = "write ${util.quote "id = \"<namespace>/<name>\";"} in ${subject}, or delete the key";
      }
    )
    ++ util.optional (isName id && declaredFold != null && foldName declaredFold == null) (
      diag.error {
        inherit subject;
        id = "interface-id-unnamed-fold";
        message = "interface ${label reg iface} claims the identity ${util.quote id} and declares a fold carrying no name";
        evidence = "a fold's name is part of the identity a claim carries and a bare function supplies none, so this claim cannot be compared with another author's; this interface is identified by its value instead";
        resolution = "write ${util.quote "fold = planner.fold \"<name>\" (set: …);"} in ${subject}, or delete the ${util.quote "id"}";
      }
    )
    ++ util.optional (isName id && match ".*[./].*" id == null) (
      diag.warning {
        inherit subject;
        id = "interface-id-unnamespaced";
        message = "interface ${label reg iface} claims the identity ${util.quote id}, which names no namespace";
        evidence = "a claim is made in a namespace shared with every other author, so an unqualified one collides silently with a stranger's claim of the same word";
        resolution = "claim ${util.quote "<domain or repository>/${id}"} in ${subject}, or leave it unqualified and accept the collision";
      }
    );

  typeLabel = t: if t == null then "no korora type" else util.quote t;

  foldLabel = n: if n == null then "no fold" else util.quote n;

  identityDifference =
    x: y:
    let
      onlyX = util.subtractList (attrNames x.exports) (attrNames y.exports);
      onlyY = util.subtractList (attrNames y.exports) (attrNames x.exports);
      shared = util.subtractList (attrNames x.exports) onlyX;
      retyped = builtins.filter (e: x.exports.${e}.type != y.exports.${e}.type) shared;
      resecreted = builtins.filter (e: x.exports.${e}.secrecy != y.exports.${e}.secrecy) shared;
    in
    if onlyX != [ ] then
      "the first declares ${util.quoteList onlyX} and the second does not"
    else if onlyY != [ ] then
      "the second declares ${util.quoteList onlyY} and the first does not"
    else if retyped != [ ] then
      "export ${util.quote (builtins.head retyped)} is ${
        typeLabel x.exports.${builtins.head retyped}.type
      } to the first and ${typeLabel y.exports.${builtins.head retyped}.type} to the second"
    else if resecreted != [ ] then
      "export ${util.quote (builtins.head resecreted)} is ${
        x.exports.${builtins.head resecreted}.secrecy
      } to the first and ${y.exports.${builtins.head resecreted}.secrecy} to the second"
    else
      "the first names ${foldLabel x.fold} and the second names ${foldLabel y.fold}";

  # A conflict is a fact about two interfaces and is observable from the registry
  # and from a wire, so one function builds it: identical bytes are what lets
  # `dedup` keep one row. Ordered by declaring file, then by the claim itself for
  # two interfaces sharing one file, so the table renders the same twice.
  claimOrder = reg: iface: util.joinLines [
    (subjectOf reg iface)
    (builtins.toJSON (identityOf iface))
  ];

  conflictRow =
    reg: x: y:
    let
      swap = claimOrder reg y < claimOrder reg x;
      first = if swap then y else x;
      second = if swap then x else y;
    in
    diag.error {
      subject = subjectOf reg first;
      id = "interface-id-conflict";
      message = "interface ${label reg first} and interface ${label reg second} both claim the identity ${
        util.quote (identityOf first).id
      }, and the two claims are not one identity";
      evidence = "an identity is the claim, each export's korora type name and secrecy, and the fold's name: ${
        identityDifference (identityOf first) (identityOf second)
      }";
      resolution = "make the two claims agree, or claim a different identity in ${subjectOf reg second}";
    };

  conflictRows =
    reg:
    let
      claimed = builtins.filter (c: c.claim != null) (
        map (r: {
          inherit (r) value;
          claim = identityOf r.value;
        }) (builtins.filter (r: isInterface r.value) reg)
      );
      ids = util.uniqueStrings (map (c: c.claim.id) claimed);
      rowsFor =
        id:
        let
          group = builtins.filter (c: c.claim.id == id) claimed;
          reference = builtins.head group;
        in
        map (c: conflictRow reg reference.value c.value) (
          builtins.filter (c: c.claim != reference.claim) group
        );
    in
    builtins.concatLists (map rowsFor ids);

  isInterface = v: isAttrs v && v ? name && v ? exports && isAttrs v.exports;

  registryRows =
    reg:
    builtins.concatLists (
      map (
        r:
        if isInterface r.value then
          atomRows reg r.value ++ foldRows reg r.value ++ idRows reg r.value
        else
          [ ]
      ) reg
    )
    ++ conflictRows reg;

  unitExtension =
    {
      backend,
      name,
      fields,
    }:
    {
      inherit backend name fields;
    };

  isUnitExtension =
    v: isAttrs v && v ? backend && isString v.backend && v ? name && v ? fields && isAttrs v.fields;

  # One extends entry. values is a subset of the extension's fields rather than an
  # equal keyset, because a hardening extension exists to set two of thirty knobs.
  readExtension =
    {
      reg,
      subject,
      where,
      application,
    }:
    let
      ext = application.extension or null;
      known = isUnitExtension ext;
      values = application.values or { };
      extLabel = if known then "unit extension ${label reg ext}" else "the extension";

      fieldRows = util.concatMapAttrsToList (
        fname: field:
        typedFieldRows {
          inherit subject;
          what = "field ${util.quote fname} of ${extLabel}";
          carrier = "a unit extension's field";
          shape = "a field";
          spelling = "a field is ${util.quote "{ type }"}";
          allowed = extensionFieldKeys;
          field = field;
          ids = {
            excluded = "unit-extension-excluded-key";
            unknown = "unit-extension-unknown-key";
            missingType = "unit-extension-missing-type";
          };
        }
      ) (if known then ext.fields else { });

      typedFields =
        if known then
          builtins.filter (fname: ext.fields ? ${fname} && isType ext.fields.${fname}.type) (attrNames values)
        else
          [ ];

      failures = builtins.filter (
        fname: ext.fields.${fname}.type.verify values.${fname} != null
      ) typedFields;

      applicationRows =
        map (
          key:
          diag.error {
            inherit subject;
            id = "implementation-unknown-key";
            message = "${where} declares ${util.quote key} on an `extends` entry, and an entry declares ${util.quoteList applicationKeys} and nothing else";
            evidence = "declared keys are ${util.quoteList (attrNames application)}";
            resolution = "delete ${util.quote key} from ${subject}";
          }
        ) (util.extraKeys applicationKeys application)
        ++ util.optional (!known) (
          diag.error {
            inherit subject;
            id = "unit-extension-missing";
            message = "${where} extends a unit with a value that is not a unit extension";
            evidence = "an extension is the value `planner.unitExtension { backend, name, fields }` returned, and it is named by that value rather than by a name resolved at composition time";
            resolution = "pass the extension value into ${subject} and write it as `extends = [ { extension = <the value>; values = { … }; } ]`";
          }
        )
        ++ map (
          key:
          diag.error {
            inherit subject;
            id = "unit-extension-unknown-field";
            message = "${where} assigns ${util.quote key} of ${extLabel}, which the extension does not declare";
            evidence = "the extension declares ${util.quoteList (attrNames ext.fields)}";
            resolution = "assign a declared field in ${subject}, or declare ${util.quote key} on the extension";
          }
        ) (if known then util.extraKeys (attrNames ext.fields) values else [ ])
        ++ map (
          fname:
          diag.error {
            inherit subject;
            id = "unit-extension-type-mismatch";
            message = "${where} assigns ${util.quote fname} of ${extLabel} a value that fails its field's type";
            evidence = "the extension declares ${fname} as ${
              util.quote ext.fields.${fname}.type.name
            }, and korora reports: ${toString (ext.fields.${fname}.type.verify values.${fname})}";
            resolution = "assign a value of that type in ${subject}, or change the field on the extension";
          }
        ) failures;
    in
    {
      backend = if known then ext.backend else null;
      name = if known then ext.name else null;
      label = extLabel;
      values = util.pickAttrs (util.subtractList typedFields failures) values;
      rows = fieldRows ++ applicationRows;
    };
}
