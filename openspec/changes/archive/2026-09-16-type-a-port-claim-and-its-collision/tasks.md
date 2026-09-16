## 1. Record what exists

- [x] 1.1 Record the current behaviour of the three defects with throwaway deployments, so each fix
  is measured against an observation rather than a description: two entries on one machine claiming
  `fixed = "5432"` and `fixed = 5432` produce no `entry-port-claimed-twice`; two entries claiming one
  number where one states `proto = "tcp"` and the other states none produce none either; and a claim
  of `{ fixed = 8000; count = 4; }` produces a row for no number at all. All three observed at
  `b7dd7e1`: the string-versus-integer deployment plans with an empty table and `alloc.ports.listen`
  of `"5432"` on one entry and `5432` on the other; the unstated-protocol deployment plans with an
  empty table, both entries recording 8000-style integer allocations; and the `count` deployment
  plans with an empty table and `alloc.ports.listen = 8000`, the fourth port of the pool claimed
  nowhere. Every one of them reported `applicable = true`.
- [x] 1.2 Record the key of `vault-repo:server@vault` and the bytes of
  `fixtures/minimal-typed-edge/plan/plan.json` and `.../diagnostics.txt` as committed, which is what
  "no golden moves" is compared against in 8.1. The golden plan is
  `fixtures/minimal-typed-edge/plan/backup.json`, not `plan.json`: the folder holds `README.md`,
  `backup.json` and `diagnostics.txt`, and `tests/unit/plan.nix:58` reads `plan/backup.json`. The
  citation was corrected here and in 8.1. Recorded: `vault-repo:server@vault` is
  `sha256-a090a60d56683eba`, `backup.json` is md5 `e0cf8b89c42656a2e91203b2895e4b42` and equal to
  `nix eval --json .#debug.worked.plan | jq -S .` at `b7dd7e1`, and `diagnostics.txt` is md5
  `3b6ec1837f78c60dd824834e4338e0c0`.

## 2. The atoms and their domains

- [x] 2.1 Add a `port` atom to `lib/atoms.nix` over an integer of 1 to 65535, and verify with a
  throwaway `verify` that `5432` passes while `"5432"`, `0`, `-1`, `65536` and `5432.0` do not. The
  bounds are `portRange`, read by the atom and by the row, so 1 and 65535 pass and `null` and an
  attrset are refused with the rest.
- [x] 2.2 Add `protocols = [ "tcp" "udp" ]` beside `restartPolicies` and `consumerCardinalities`
  (`lib/atoms.nix:15-28`), a `protocol` atom over it, and `domains.protocol` beside
  `domains.restartPolicy` (`lib/atoms.nix:67-75`), and verify the domain list is read by both the
  atom and the row rather than written twice. `"tcp"` and `"udp"` pass, `"TCP"`, `"sctp"`, the empty
  string, `null` and an integer are refused, and `readClaims` quotes `atoms.domains.protocol` rather
  than a second copy of the two values.
- [x] 2.3 Add a `bindAddress` atom admitting a non-empty string of `[0-9A-Za-z:._%-]` and refusing
  `0.0.0.0`, `::`, `[::]` and `*`, and verify with a throwaway `verify` that `10.0.0.11`,
  `fd00::1` and `db.internal` pass while the four wildcard spellings, the empty string and a
  non-string do not. `fe80::1%eth0` passes too, which is why the zone character is in the grammar.

## 3. The claim reading

- [x] 3.1 Change `claimKeys` in `lib/module.nix:115-119` to `[ "proto" "fixed" "address" ]`, and
  verify a claim writing `count` now earns `declaration-unknown-key` naming the key and listing the
  three - which is `testAPortClaimDeclaringCount`. The message reads "declares `count`, and this
  subset reads `proto`, `fixed`, `address`".
- [x] 3.2 Add `port-claim-not-a-port` to `readClaims` (`lib/module.nix:326-366`), verify the row
  names the claim, the value and the range, and verify the claim is absent from `alloc.ports` the
  way a claim with no `fixed` already is (`lib/module.nix:355`). The value is named through korora's
  own report, the way `unit-field-type-mismatch` names one, and the entry records no `alloc` at all
  where the claim was its only one.
- [x] 3.3 Add `port-claim-protocol-unknown` naming every value of `domains.protocol`, and
  `port-claim-address-malformed` whose resolution names omitting the field for the wildcard. Verify
  both leave the number recorded and the refused field unset, which is
  `testAClaimWhoseProtocolIsRefusedKeepsItsNumber`.
- [x] 3.4 Have `readClaims` return a normalised claim - `{ fixed, proto, address }` with `null` for
  an unstated or refused field - rather than the module's own attrset, and verify by evaluating a
  member whose module wrote a claim with a refused protocol that the record the resolver is handed
  carries no protocol. This is what stops the index reading around the validation, which it does
  today at `lib/plan.nix:706`. Observed as `testARefusedProtocolCollidesWithEveryProtocol`: the
  refused claim contends with a `udp` claim of the same number, which only a `proto` of `null` does.
- [x] 3.5 Verify `lib/resolve.nix:941-943` is untouched and `alloc.ports` is still the number alone,
  which is what keeps `keyInput.alloc` (`lib/plan.nix:802`) still - `testTheEntryRecordsTheNumberAlone`.
  `git diff` names no file under `lib/` other than `atoms.nix`, `module.nix` and `plan.nix`.

## 4. Every module that must lose one word

- [x] 4.1 Delete the `count` line from the two perf inputs, `perf/fleet.nix:90` and
  `perf/mesh.nix:102`, and verify both still plan by running the `perf` unit suite, which plans
  `fleet` at size 64 and compares plans rather than deployments; the gated counters are 8.3. The
  `perf` suite is green, and both fixtures plan the same entry counts they did: 49 for `fleet-16`,
  193 for `fleet-64`.
- [x] 4.2 Delete it from `fixtures/minimal-typed-edge/modules/borg-repo/server.nix:16`, and verify
  the evaluated plan is byte-equal to the golden recorded in 1.2, `count` being in no plan field.
- [x] 4.3 Delete it from the unit suites' own deployments: `tests/unit/composition.nix:54`,
  `tests/unit/composition.nix:217`, `tests/unit/plan.nix:276` (the `claimsPort` helper),
  `tests/unit/plan.nix:927` and `tests/unit/postgres.nix:45`. Verify each suite is green on its own.
- [x] 4.4 Delete it from the four end-to-end modules:
  `tests/e2e/generated-secret/deployment/modules/issuer/api.nix:15`,
  `tests/e2e/secret-delivery/deployment/modules/issuer/api.nix:13`,
  `tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:28` and
  `tests/e2e/wired-pair/deployment/modules/page/server.nix:13`. Verify each folder's deployment
  still evaluates applicable with `planner build`. `wired-pair` and `shared-postgres` are verified by
  the run in 8.4, which builds each deployment with `planner build` before it applies it;
  `secret-delivery` and `generated-secret` were verified by reading the deployment build's own
  `diagnostics` off `packages.planner-e2e-<folder>`, which is empty for both, and an empty table
  carries no error row.
- [x] 4.5 Verify nothing else writes it: a search for `count` under `lib/`, `fixtures/`, `perf/`,
  `tests/` and `docs/` returns only occurrences that are not a claim key. Twelve claim sites in ten
  files, exactly the list the proposal's Impact enumerates and no site it missed. What the search
  also returns and what is not a claim: `util.countWord`/`countNoun` and their callers, the
  `countById` test helper, `reach-one-placement-count`, `perf/check.py`'s counter vocabulary,
  `perf/eval.nix`'s entry count, prose in the fixture READMEs and in `docs/`, and the `count`
  attributes of test expectations - including `count = 1;` in `tests/unit/plan.nix`,
  `diagnostics.nix`, `operator.nix` and `vars.nix`, which are row counts and not claims.

## 5. The collision index

- [x] 5.1 Rewrite `portsOf` (`lib/plan.nix:701-709`) to carry the normalised claim as a record -
  number, protocol, address - rather than the string `"<proto>/<toJSON fixed>"`, delete the
  `builtins.toJSON`, and verify the claims of `vault-repo:server@vault` read as one record carrying
  the integer. `portsOf` is now `attrValues member.declaration.claims.ports`, and that entry's
  claims read `[ { address = null; fixed = 22; proto = "tcp"; } ]`.
- [x] 5.2 Adjust `claimsOf` (`lib/plan.nix:714-726`) so a port claim survives as a record while a
  path and a directory stay strings, keeping the per-entry deduplication, and verify two units of one
  entry still claim one directory once. A port claim deduplicates with `util.distinct`, which is the
  helper for values no key can be built from, and the other two keep `util.uniqueStrings`;
  `testTwoUnitsOfOneEntryShareItsDirectory` is green.
- [x] 5.3 Add the overlap step to `collisionRows` (`lib/plan.nix:733-757`): group by machine and then
  by number, bucket identical protocol-and-address spellings, emit one row per bucket with more than
  one claimant and one row per pair of buckets whose spellings overlap. Verify with the throwaway
  deployments of 1.1 that the string case is now one `port-claim-not-a-port` and the unstated
  protocol case is one `entry-port-claimed-twice`. Both observed, and the `count` case is now one
  `declaration-unknown-key`. A claim an entry makes twice is still the entry's own: the claimant
  count is taken after deduplication, so a member writing one number under two claim names earns no
  row.
- [x] 5.4 Restate the port resource's evidence and resolution (`lib/plan.nix:648-656`) over the
  address: the current evidence, "one machine carries one listener per protocol and port", is the
  sentence that asserted the address away. Verify the row names the protocol and the address the
  contention is on and resolves to stating an address or a different number. The message reads
  "entries `a`, `b` placed on `one` all claim the port `5432` on protocol `tcp` and address
  `10.0.0.11`", and where a field is unstated on both sides it says "every protocol of the domain"
  or "every address of the machine" rather than naming an absence.
- [x] 5.5 Verify the rows are built with the `row`/`error`/`warning` constructors and that
  `tests/unit/diagnostics.nix` stays green: the purity scan finds no `throw`, `abort`, `assert`,
  `.check ` or `korora.check` in `lib/*.nix`, and the row-versus-refusal cross-walk accounts for the
  three new identifiers. All four rows are `diag.error`; the reading calls `verify` and never
  `check`. No realiser refuses on account of a claim, so the cross-walk owes the three identifiers
  no account, and `diagnostics.testTheLibraryGainsARow` is what they do owe: it named
  `docs/diagnostics.md` until 7.3 tabulated them.

## 6. The scenarios

- [x] 6.1 Add the vocabulary scenarios to `tests/unit/composition.nix`, beside the existing
  `port-claim-not-fixed` coverage at `:818-825`: `testAPortNumberWrittenAsAString`,
  `testAPortNumberOutsideTheRange`, `testAPortClaimDeclaringCount`,
  `testAClaimWhoseProtocolIsRefusedKeepsItsNumber`, `testAProtocolOutsideTheDomain`,
  `testAnAddressSpelledAsTheWildcard` and `testAnAddressOutsideTheAddressGrammar`. Each asserts the
  identifier, the severity, and that the message names the claim and what the field may take; verify
  each is red against the unpatched tree. Verified by evaluating every scenario's deployment against
  the base library extracted from `b7dd7e1`: each of the seven rows is produced 0 times there and
  once here, and the string case also shows the collision the base tree reported for it - none.
- [x] 6.2 Add the record and key scenarios to `tests/unit/plan.nix`:
  `testTheEntryRecordsTheNumberAlone`, `testAClaimThatStatesAnAddressKeysAsItDid` and
  `testAnAddressADeploymentMovesReKeysThroughSettings`. The second compares the key of an entry
  before and after the address is stated and expects equality; the third moves the setting the
  address is built from and expects the key to move and a sibling's key to stay. The first two are
  red against the base library for the row list rather than for the record: an `address` is an
  unknown claim key there, so both deployments earn `declaration-unknown-key` and the second's two
  keys are equal for the wrong reason.
- [x] 6.3 Add the collision scenarios to `tests/unit/plan.nix`:
  `testOneClaimStatesAProtocolAndTheOtherStatesNone`, `testTwoClaimsOfOneNumberBindTwoAddresses`,
  `testAWildcardClaimAndASpecificClaimOfOneNumber` and
  `testARefusedProtocolCollidesWithEveryProtocol`. Verify the second produces no row and an
  applicable plan, and the other three produce exactly one `entry-port-claimed-twice` each. Three of
  the four are red against the base library by their row count: the unstated protocol produces 0
  there, the two addresses produce 1, and the refused protocol produces 0. The wildcard case
  produces one row on both sides and is red on its message, which on the base tree can name no
  address: the two claims collided there because the address was not read at all.
- [x] 6.4 Amend the two existing collision tests the change touches -
  `testTwoEntriesOnOneMachineClaimOnePort` (`tests/unit/plan.nix:2195`) and
  `testACollisionIsReportedOnceAndNamesBothEntries` (`:2335`) - so the claims they build state one
  protocol and one address, and verify the first still finds no row for a TCP and a UDP claim of one
  number and the second still produces one row over three claimants. Both hold, and each now also
  asserts the address in the message; the `claimsPort` helper takes the address as a third argument,
  `null` standing for a field the module leaves unstated.

## 7. Registration and documentation

- [x] 7.1 Move this change's two spec files from `excused` to `accountable` in
  `tests/unit/coverage.nix`, the excuse expiring the moment a task here is ticked, and verify
  `testEverySpecificationIsClassified` and the scenario cross-walk are green: every scenario heading
  of both files finds the test name it derives.
- [x] 7.2 Update `docs/tooling.md`'s per-suite figures for `composition` and `plan` and the prose
  total, which this change moves by fourteen tests, and verify `testASuiteGainsATest` is green.
  `composition` 32 to 39, `plan` 47 to 54, the total 507 to 521.
- [x] 7.3 Rewrite the claim row of `docs/authoring.md:142` as `{ proto, fixed, address }` with the
  domain, the range and the wildcard default stated, and add the three new identifiers to
  `docs/diagnostics.md:130` beside `port-claim-not-fixed`.
- [x] 7.4 Rewrite `docs/diagnostics.md:244`, which today states the protocol rule as though it were
  checked, over what the row now compares: the number, the protocol with an unstated one colliding
  with every protocol, and the address with an unstated one being the wildcard. Verify
  `nix build .#checks.x86_64-linux.treefmt` passes, vale included. It exits 0.
- [x] 7.5 Record the invariant in `CLAUDE.md` under Diagnostics, beside the paragraph about what two
  entries of one machine claim: the claim's three typed fields, why an unstated protocol is the wide
  reading and an unstated address is the wildcard, why a refused protocol or address widens the claim
  while a refused number drops it, and why neither reaches `alloc` or the entry key.

## 8. Verification

- [x] 8.1 Verify no golden moved: `nix eval --json .#debug.worked.plan | jq -S .` equals
  `fixtures/minimal-typed-edge/plan/backup.json` as committed, and `diagnostics.txt` is
  byte-identical to the copy recorded in 1.2. Both hold: the regenerated plan is byte-identical to
  the committed `backup.json` and to the copy taken at `b7dd7e1`, `vault-repo:server@vault` is still
  `sha256-a090a60d56683eba`, and neither golden file is in `git diff`.
- [x] 8.2 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the fixture comparison and the `tests/unit/diagnostics.nix` cross-walks. It exits 0, and
  `nix eval --json .#debug.failures` is `[ ]` over all nineteen suites.
- [x] 8.3 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The
  claim index is evaluated per entry and both perf inputs claim one port per entry, so record the
  measured cost per entry at sizes 64 and 256 if the margin moved by more than half of the 0.15
  allowance. It fails, as it does before this change: 81 of 81 gated figures are above their
  recorded budgets on both sides, by 0.09% to 12.7% at the base library and by 0.16% to 12.3% here.
  The comparison was made by running `perf/measure.sh` twice over the same perf inputs, once with
  `--lib` pointing at the library extracted from `b7dd7e1` and once at this one. The largest
  movement of any gated figure is +0.91%, well inside half of the 0.15 allowance, and four of the
  nine counters fall. `nrThunks` per entry, base against this change: `fleet-64` 390.76 against
  389.80, `fleet-256` 369.97 against 368.73, `mesh-64` 459.21 against 458.25, `mesh-256` 438.83
  against 437.59. `gc.totalBytes` per entry: `fleet-64` 21865.12 against 21840.58, `fleet-256`
  20629.28 against 20628.62, `mesh-64` 26238.67 against 26256.58, `mesh-256` 25044.64 against
  25038.65. The growth bound of 1.25 holds on both sides and is unmoved to two digits: every ratio
  against size 4 falls rather than grows, and every ratio here is at or below the base one, so the
  pairwise step added no growth term. The gated check itself was then run on both sides rather than
  only `perf/measure.sh`: `nix build .#checks.x86_64-linux.planner-perf` here and the same
  attribute of the `b7dd7e1` tree, both reporting `81 failures, 0 invalid comparisons, 81 of 81
  gated figures compared`, and both reproducing the eight figures above.
- [x] 8.4 Run `nix run .#planner-e2e -- wired-pair` and `nix run .#planner-e2e -- shared-postgres`
  and verify neither folder regressed: both write a claim that loses its `count`, and
  `shared-postgres` is the folder that runs two clusters on one machine on two numbers. One command
  naming both folders does not work: `tests/e2e/runner.py:332` reads at most one folder name and
  passes the rest to pytest, so `nix run .#planner-e2e -- wired-pair shared-postgres` fails with
  "file or directory not found: shared-postgres" before any machine boots. The task now names two
  runs.
