## 1. Reproduce each refusal above an empty table

- [ ] 1.1 Write a throwaway deployment whose generator declares no `program`, build it through
  `operator.mkGeneration`, and record that `mkPlan` answers `applicable = true` with an empty table
  while the build aborts with `planner secrets: entry … records no "program"`
- [ ] 1.2 Do the same for a generated file named `.nixos-secrets-metadata` and for one named
  `key@id`, and record the abort and the empty table for each
- [ ] 1.3 Do the same for a value delivered to a machine whose registry record declares no address,
  and record that the table carries a warning at most rather than an error
- [ ] 1.4 Do the same for a machine whose declared address carries a space, and record that
  `secrets/backend.nix` aborts on the shell word rule
- [ ] 1.5 Delete the throwaway deployments; the recorded observations go in the change, nothing in
  the tree

## 2. The reading gains its rows half

- [ ] 2.1 Add `rows { plan, backend }` to `secrets/read.nix` returning rows built with
  `planner.error`/`planner.warning`, with one description per condition shared with the refusal it
  pairs with, and verify by evaluating it over each plan from group 1
- [ ] 2.2 Row the value-level conditions: no `program`, no `deploy`, no `files`, a file with no
  `path`, and a plan key that is not a generated value's key; verify one row per condition naming the
  entry and the field
- [ ] 2.3 Row the name conditions: a component carrying the separator, a component outside the
  contract's grammar, a file name outside the file grammar, the reserved provenance name, and two
  keys projecting onto one name; verify the collision row names both keys and the name
- [ ] 2.4 Row the delivery conditions: a recipient machine with no `machine:<name>` entry, one whose
  entry records no address, and an address or path the rendered step cannot carry as one shell word;
  verify each row names the value and the machine
- [ ] 2.5 Verify `rows` realises nothing by evaluating it under `nix eval --json` over
  `fixtures/minimal-typed-edge` and confirming the result is a list of records carrying no store path

## 3. Every refusal carries its account

- [ ] 3.1 Change `fail` in `secrets/read.nix` and `secrets/backend.nix` to take
  `{ id, message }` or `{ id = null; because; }`, give every site its row identifier, and export the
  accounts as a value; verify each refusal still raises the same sentence
- [ ] 3.2 Do the same for every `fail` in `image/read.nix` and `flakelet/read.nix`, taking each
  identifier from the fragment table the suite currently holds; verify no refusal's message text
  changes
- [ ] 3.3 Verify each account's identifier is produced by a producing layer, by crossing the exported
  accounts against the row identifiers of `lib/*.nix`, `operator/read.nix` and the new secrets rows

## 4. The generation build carries its table

- [ ] 4.1 Build the table in `operator.mkGeneration` from `result.diagnostics` and the reading's rows
  through `planner.mkTable`, and verify the rendered text is one table ordered by identifier, subject
  and message
- [ ] 4.2 Write `diagnostics.json` and `diagnostics.txt` into the generation farm beside
  `secrets.json`, `names.json` and `plan.nix`, and verify both files exist for a plan with an empty
  table
- [ ] 4.3 Refuse the build with `planner.render` of the whole table when it holds an error, and verify
  each plan from group 1 now refuses with a table naming the condition rather than with a
  `planner secrets:` sentence
- [ ] 4.4 Verify a table carrying warnings and no error still builds every file of the farm

## 5. The accounting covers every realiser

- [ ] 5.1 Replace `refusalsAccountedFor` and `accountingOf` in `tests/unit/diagnostics.nix` with a
  lookup over the accounts the realisers export, and verify the suite still fails for a refusal whose
  account names no produced row
- [ ] 5.2 Derive the covered realiser set from the realiser sources the suite is handed rather than
  from `realiserFiles`, and verify by removing an account from a secrets refusal that the suite fails
  naming it
- [ ] 5.3 Verify a reworded refusal message leaves the suite green, by rewording one refusal in
  `image/read.nix` and running the suite with no test edited

## 6. Suites and documents

- [ ] 6.1 Add tests to `tests/unit/secrets.nix` for every scenario of the
  `realiser/secrets-configuration` delta, and verify each fails against the current reading and
  passes against the new one
- [ ] 6.2 Add the two `tooling/test-layers` scenarios to `tests/unit/diagnostics.nix` and verify each
  can fail by breaking exactly what it names
- [ ] 6.3 Register every new scenario in `tests/unit/coverage.nix` under `accountable`, and verify
  `nix build .#checks.x86_64-linux.planner-unit` reports no unmapped scenario
- [ ] 6.4 Document the new rows in `docs/diagnostics.md` under the secrets reading and the two halves
  of the generation build in `docs/secrets.md`, and verify `nix build .#checks.x86_64-linux.treefmt`
  passes
- [ ] 6.5 Update `CLAUDE.md` so the layered rule names three realisers and states that a refusal
  carries its own row identifier, and verify the literal assertions in `tests/unit/layers.nix` still
  hold
- [ ] 6.6 Run `nix build .#checks.x86_64-linux.planner-unit` and the secrets end-to-end folder, and
  verify both pass with no golden regenerated
