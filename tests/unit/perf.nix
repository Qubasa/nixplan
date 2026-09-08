# The two properties of the measurement harness that are properties of a value
# rather than of a run: the synthetic fleet is a pure function of its size, and
# nothing the harness evaluates asks to be built.
#
# Everything else in specs/tooling/evaluation-performance/ is about an
# interpreter run and is asserted by the checker's own suite,
# perf/check_test.py, which tests/unit/coverage.nix names test by test.
{ planner, support }:
let
  inherit (builtins)
    attrNames
    concatLists
    filter
    isAttrs
    isList
    isString
    length
    match
    readFile
    ;

  inherit (support) perfSource hasInfix;

  fixtureOf = name: size: import (perfSource + "/${name}.nix") { inherit planner size; };

  fleetOf = fixtureOf "fleet";

  meshOf = fixtureOf "mesh";

  fleetText = readFile (perfSource + "/fleet.nix");

  meshText = readFile (perfSource + "/mesh.nix");

  # Every string in a value that is shaped like a store path. A measurement
  # realises nothing, so each one has to be a string the fixture wrote rather
  # than a derivation Nix would build.
  storePathStrings =
    node:
    if isAttrs node then
      concatLists (map (k: storePathStrings node.${k}) (attrNames node))
    else if isList node then
      concatLists (map storePathStrings node)
    else if isString node && match "/nix/store/.*" node != null then
      [ node ]
    else
      [ ];

  # A derivation or a path in the plan would be a value the harness asked Nix
  # to produce. `builtins.toJSON` over the plan already refuses a function; this
  # looks for the two things it would happily serialise.
  derivationsIn =
    node:
    if isAttrs node then
      (if node ? outPath || node ? drvPath then [ node ] else [ ])
      ++ concatLists (map (k: derivationsIn node.${k}) (attrNames node))
    else if isList node then
      concatLists (map derivationsIn node)
    else
      [ ];

  ambient = [
    "currentTime"
    "currentSystem"
    "getEnv"
    "readFile"
    "readDir"
    "fetchTree"
    "fetchurl"
    "storePath"
    "derivation"
  ];
in
{
  # Scenario: The synthetic fleet is deterministic. Two generations at one size
  # produce the same plan, so a comparison across sizes compares the library
  # and not the fixture.
  #
  # The comparison is over the plan rather than over the deployment: a
  # deployment carries module functions, two of which are never equal in Nix
  # however identically they were written, while a plan is free of expressions
  # by construction and is exactly what a measurement forces.
  testTheSyntheticFleetIsDeterministic =
    let
      planAt = size: (planner.mkPlan (fleetOf size)).plan;
    in
    {
      expr = {
        four = planAt 4 == planAt 4;
        # Sixty-four rather than the largest budgeted size, because this suite
        # plans it twice and the growth bound already measures 256.
        sixtyFour = planAt 64 == planAt 64;
        # Two sizes are not equal to each other, or the property above would
        # hold of a generator that ignored its argument.
        differentSizesDiffer = planAt 4 != planAt 16;
        machinesAtFour = length (attrNames (fleetOf 4).machines);
        machinesAtSixteen = length (attrNames (fleetOf 16).machines);
      };
      expected = {
        four = true;
        sixtyFour = true;
        differentSizesDiffer = true;
        machinesAtFour = 4;
        machinesAtSixteen = 16;
      };
    };

  # The generator reads no ambient value, which is what makes the equality above
  # a property of the file rather than of the moment it ran.
  testTheFleetReadsNoAmbientValue = {
    expr = filter (name: hasInfix name fleetText) ambient;
    expected = [ ];
  };

  # The mesh fixture is the other shape a measurement needs, and it is a pure
  # function of its size for the same reason.
  testTheSyntheticMeshIsDeterministic =
    let
      planAt = size: (planner.mkPlan (meshOf size)).plan;
    in
    {
      expr = {
        four = planAt 4 == planAt 4;
        differentSizesDiffer = planAt 4 != planAt 16;
        machinesAtSixteen = length (attrNames (meshOf 16).machines);
      };
      expected = {
        four = true;
        differentSizesDiffer = true;
        machinesAtSixteen = 16;
      };
    };

  testTheMeshReadsNoAmbientValue = {
    expr = filter (name: hasInfix name meshText) ambient;
    expected = [ ];
  };

  # What the mesh fixture exists to measure: one entry whose units, closure
  # roots and render fragments each number one per machine, in a plan that is
  # still linear in the fleet. A fixture that collapsed any of those into a
  # single item would keep measuring and stop covering the shape, which is how
  # this coverage is lost without a test.
  testTheMeshPlansOneFleetSizedEntry =
    let
      result = planner.mkPlan (meshOf 16);
      hub = result.plan."hub:hub@m0";
    in
    {
      expr = {
        errors = filter (r: r.severity == "error") result.diagnostics;
        entries = length (attrNames result.plan);
        units = length (attrNames hub.units);
        closure = length hub.closure;
        fragments = length hub.configData."/etc/mesh/peers".render;
        readEntries = length (attrNames hub.reads.peers.entries);
      };
      expected = {
        errors = [ ];
        entries = 33;
        units = 17;
        closure = 17;
        fragments = 16;
        readEntries = 16;
      };
    };

  # Scenario: The harness is asked to build. Every package the fleet names is a
  # literal store path string, so the plan carries no derivation and the
  # measurement has nothing to realise.
  testTheHarnessIsAskedToBuild =
    let
      plan = (planner.mkPlan (fleetOf 16)).plan;
      paths = storePathStrings plan;
    in
    {
      expr = {
        derivations = length (derivationsIn plan);
        everyStorePathIsAString = paths == filter isString paths;
        atLeastOneStorePathIsRecorded = paths != [ ];
      };
      expected = {
        derivations = 0;
        everyStorePathIsAString = true;
        atLeastOneStorePathIsRecorded = true;
      };
    };
}
