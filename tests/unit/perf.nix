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
  testTheSyntheticFleetIsDeterministic =
    let
      planAt = size: (planner.mkPlan (fleetOf size)).plan;
    in
    {
      expr = {
        four = planAt 4 == planAt 4;
        sixtyFour = planAt 64 == planAt 64;
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

  testTheFleetReadsNoAmbientValue = {
    expr = filter (name: hasInfix name fleetText) ambient;
    expected = [ ];
  };

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
