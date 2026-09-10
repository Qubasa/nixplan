# Interfaces, export atoms and the typed extensions a backend adds to the unit
# vocabulary.
#
# An interface is the value an author imported. It is identified by that value and
# never by a name resolved at composition time, it is validated against no
# registry, and its name is a label that appears in diagnostic output and nowhere
# else. Two interfaces in two files may carry one name, and a unit extension is
# the same construction under the same rule.
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

  secrecyOf = atom: atom.secrecy or "public";

  exportNames = iface: attrNames iface.exports;

  secretExports =
    iface: builtins.filter (e: secrecyOf iface.exports.${e} == "secret") (exportNames iface);

  # An interface's declaring file, found by value in the registry the caller passed
  # to mkPlan. A miss is not an error: the registry exists so a row can print a
  # file beside a name, not so an interface can be rejected for being absent.
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
    in
    if hits == [ ] then null else (builtins.head hits).file;

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
  foldRows =
    reg: iface:
    let
      subject = subjectOf reg iface;
      fold = foldOf iface;
    in
    util.optional (fold != null && !isFunction fold) (
      diag.error {
        inherit subject;
        id = "interface-fold-not-a-function";
        message = "interface ${label reg iface} declares a fold that is not a function";
        evidence = "a fold is applied to the set a read collects, keyed by provider entry key, and returns the value the consuming implementation receives";
        resolution = "write ${util.quote "fold = set: …;"} in ${subject}, or delete the key";
      }
    );

  isInterface = v: isAttrs v && v ? name && v ? exports && isAttrs v.exports;

  registryRows =
    reg:
    builtins.concatLists (
      map (r: if isInterface r.value then atomRows reg r.value ++ foldRows reg r.value else [ ]) reg
    );

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
