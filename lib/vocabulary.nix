# The authoring vocabulary as data, projected from the tables the readings above
# already run on and restating none of them: a key list is the list the reading
# admits a key against, a unit field's type is the korora typedef the reading
# verifies it with, and a directory kind is the table that decides both. A field
# added to one of those tables is described here by existing.
#
# It describes and never validates. The validator is `mkPlan` and its answer is a
# row, so what a key admits is here as a type's name and, where the type is an
# enumeration, as the values it takes. A predicate is a function: it can be named
# and not serialised, which is the limit a claimed identity already compares type
# names under, and `atoms.domains` is read for its list-valued members alone
# because one predicate rides that table.
{
  atoms,
  excluded,
  module,
  resolve,
  util,
}:
{
  # Two sentences a reader of the file gets without this repository beside it. The
  # second names a document and a section and carries no sentence of either: the
  # sentences have one home and the data has another.
  describes = "This record names what a deployment may declare and judges nothing. A deployment is judged by planning it, and the answer is a diagnostics row.";

  validator = "planner.mkPlan";

  # The conditions the interpreter does not let this library catch, which is why
  # they are a document rather than a row.
  failures = {
    document = "docs/authoring.md";
    section = "What ends an evaluation";
  };

  # Which keys each half of a declaration may carry, one entry per table a
  # reading holds.
  declarations = {
    machine = resolve.machineRegistryKeys;
    reservation = resolve.reservationKeys;
    instance = resolve.instanceKeys;
    placement = resolve.everyKeys;
    module = module.moduleKeys;
    impl = module.implKeys;
    unit = module.unitKeys;
    configFile = module.configFileKeys;
  };

  # A unit field and the name of the type its value is held to. The name is what
  # the field-type row prints, so this is that row's own reading of the same
  # table.
  unitFields = builtins.mapAttrs (_: typedef: typedef.name) module.unitVocabulary;

  # The kinds of directory a unit may declare, as the kind-to-mode-field map they
  # are: two keys of the unit vocabulary per kind, derived rather than spelled.
  directoryKinds = module.directoryKinds;

  # The values an enumerated type admits, keyed by that type's name. Filtered to
  # the list-valued members, because a member of this table may legitimately be a
  # predicate and serialising a function ends the evaluation that would report it.
  domains = util.filterAttrs (_: domain: builtins.isList domain) atoms.domains;

  # The range a port is an integer of, as text: every leaf of this record is a
  # string, a list of strings or a record of those, so one decode reads all of it.
  portRange = builtins.mapAttrs (_: bound: toString bound) atoms.portRange;

  # The constructs a deployment may not write, with the condition that would
  # bring each one back. Embedded rather than described: it is already data with
  # one home.
  inherit excluded;
}
