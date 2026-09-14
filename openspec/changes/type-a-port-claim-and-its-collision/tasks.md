## 1. Record what exists

- [ ] 1.1 Record the current behaviour of the three defects with throwaway deployments, so each fix
  is measured against an observation rather than a description: two entries on one machine claiming
  `fixed = "5432"` and `fixed = 5432` produce no `entry-port-claimed-twice`; two entries claiming one
  number where one states `proto = "tcp"` and the other states none produce none either; and a claim
  of `{ fixed = 8000; count = 4; }` produces a row for no number at all
- [ ] 1.2 Record the key of `vault-repo:server@vault` and the bytes of
  `fixtures/minimal-typed-edge/plan/plan.json` and `.../diagnostics.txt` as committed, which is what
  "no golden moves" is compared against in 8.1

## 2. The atoms and their domains

- [ ] 2.1 Add a `port` atom to `lib/atoms.nix` over an integer of 1 to 65535, and verify with a
  throwaway `verify` that `5432` passes while `"5432"`, `0`, `-1`, `65536` and `5432.0` do not
- [ ] 2.2 Add `protocols = [ "tcp" "udp" ]` beside `restartPolicies` and `consumerCardinalities`
  (`lib/atoms.nix:15-28`), a `protocol` atom over it, and `domains.protocol` beside
  `domains.restartPolicy` (`lib/atoms.nix:67-75`), and verify the domain list is read by both the
  atom and the row rather than written twice
- [ ] 2.3 Add a `bindAddress` atom admitting a non-empty string of `[0-9A-Za-z:._%-]` and refusing
  `0.0.0.0`, `::`, `[::]` and `*`, and verify with a throwaway `verify` that `10.0.0.11`,
  `fd00::1` and `db.internal` pass while the four wildcard spellings, the empty string and a
  non-string do not

## 3. The claim reading

- [ ] 3.1 Change `claimKeys` in `lib/module.nix:115-119` to `[ "proto" "fixed" "address" ]`, and
  verify a claim writing `count` now earns `declaration-unknown-key` naming the key and listing the
  three - which is `testAPortClaimDeclaringCount`
- [ ] 3.2 Add `port-claim-not-a-port` to `readClaims` (`lib/module.nix:326-366`), verify the row
  names the claim, the value and the range, and verify the claim is absent from `alloc.ports` the
  way a claim with no `fixed` already is (`lib/module.nix:355`)
- [ ] 3.3 Add `port-claim-protocol-unknown` naming every value of `domains.protocol`, and
  `port-claim-address-malformed` whose resolution names omitting the field for the wildcard. Verify
  both leave the number recorded and the refused field unset, which is
  `testAClaimWhoseProtocolIsRefusedKeepsItsNumber`
- [ ] 3.4 Have `readClaims` return a normalised claim - `{ fixed, proto, address }` with `null` for
  an unstated or refused field - rather than the module's own attrset, and verify by evaluating a
  member whose module wrote a claim with a refused protocol that the record the resolver is handed
  carries no protocol. This is what stops the index reading around the validation, which it does
  today at `lib/plan.nix:706`
- [ ] 3.5 Verify `lib/resolve.nix:941-943` is untouched and `alloc.ports` is still the number alone,
  which is what keeps `keyInput.alloc` (`lib/plan.nix:802`) still - `testTheEntryRecordsTheNumberAlone`

## 4. Every module that must lose one word

- [ ] 4.1 Delete the `count` line from the two perf inputs, `perf/fleet.nix:90` and
  `perf/mesh.nix:102`, and verify both still plan by running the `perf` unit suite, which plans
  `fleet` at size 64 and compares plans rather than deployments; the gated counters are 8.3
- [ ] 4.2 Delete it from `fixtures/minimal-typed-edge/modules/borg-repo/server.nix:16`, and verify
  the evaluated plan is byte-equal to the golden recorded in 1.2, `count` being in no plan field
- [ ] 4.3 Delete it from the unit suites' own deployments: `tests/unit/composition.nix:54`,
  `tests/unit/composition.nix:217`, `tests/unit/plan.nix:276` (the `claimsPort` helper),
  `tests/unit/plan.nix:927` and `tests/unit/postgres.nix:45`. Verify each suite is green on its own
- [ ] 4.4 Delete it from the four end-to-end modules:
  `tests/e2e/generated-secret/deployment/modules/issuer/api.nix:15`,
  `tests/e2e/secret-delivery/deployment/modules/issuer/api.nix:13`,
  `tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:28` and
  `tests/e2e/wired-pair/deployment/modules/page/server.nix:13`. Verify each folder's deployment
  still evaluates applicable with `planner build`
- [ ] 4.5 Verify nothing else writes it: a search for `count` under `lib/`, `fixtures/`, `perf/`,
  `tests/` and `docs/` returns only occurrences that are not a claim key

## 5. The collision index

- [ ] 5.1 Rewrite `portsOf` (`lib/plan.nix:701-709`) to carry the normalised claim as a record -
  number, protocol, address - rather than the string `"<proto>/<toJSON fixed>"`, delete the
  `builtins.toJSON`, and verify the claims of `vault-repo:server@vault` read as one record carrying
  the integer
- [ ] 5.2 Adjust `claimsOf` (`lib/plan.nix:714-726`) so a port claim survives as a record while a
  path and a directory stay strings, keeping the per-entry deduplication, and verify two units of
  one entry still claim one directory once
- [ ] 5.3 Add the overlap step to `collisionRows` (`lib/plan.nix:733-757`): group by machine and then
  by number, bucket identical protocol-and-address spellings, emit one row per bucket with more than
  one claimant and one row per pair of buckets whose spellings overlap. Verify with the throwaway
  deployments of 1.1 that the string case is now one `port-claim-not-a-port` and the unstated
  protocol case is one `entry-port-claimed-twice`
- [ ] 5.4 Restate the port resource's evidence and resolution (`lib/plan.nix:648-656`) over the
  address: the current evidence, "one machine carries one listener per protocol and port", is the
  sentence that asserted the address away. Verify the row names the protocol and the address the
  contention is on and resolves to stating an address or a different number
- [ ] 5.5 Verify the rows are built with the `row`/`error`/`warning` constructors and that
  `tests/unit/diagnostics.nix` stays green: the purity scan finds no `throw`, `abort`, `assert`,
  `.check ` or `korora.check` in `lib/*.nix`, and the row-versus-refusal cross-walk accounts for the
  three new identifiers

## 6. The scenarios

- [ ] 6.1 Add the vocabulary scenarios to `tests/unit/composition.nix`, beside the existing
  `port-claim-not-fixed` coverage at `:818-825`: `testAPortNumberWrittenAsAString`,
  `testAPortNumberOutsideTheRange`, `testAPortClaimDeclaringCount`,
  `testAClaimWhoseProtocolIsRefusedKeepsItsNumber`, `testAProtocolOutsideTheDomain`,
  `testAnAddressSpelledAsTheWildcard` and `testAnAddressOutsideTheAddressGrammar`. Each asserts the
  identifier, the severity, and that the message names the claim and what the field may take; verify
  each is red against the unpatched tree
- [ ] 6.2 Add the record and key scenarios to `tests/unit/plan.nix`:
  `testTheEntryRecordsTheNumberAlone`, `testAClaimThatStatesAnAddressKeysAsItDid` and
  `testAnAddressADeploymentMovesReKeysThroughSettings`. The second compares the key of an entry
  before and after the address is stated and expects equality; the third moves the setting the
  address is built from and expects the key to move and a sibling's key to stay
- [ ] 6.3 Add the collision scenarios to `tests/unit/plan.nix`:
  `testOneClaimStatesAProtocolAndTheOtherStatesNone`, `testTwoClaimsOfOneNumberBindTwoAddresses`,
  `testAWildcardClaimAndASpecificClaimOfOneNumber` and
  `testARefusedProtocolCollidesWithEveryProtocol`. Verify the second produces no row and an
  applicable plan, and the other three produce exactly one `entry-port-claimed-twice` each
- [ ] 6.4 Amend the two existing collision tests the change touches -
  `testTwoEntriesOnOneMachineClaimOnePort` (`tests/unit/plan.nix:2195`) and
  `testACollisionIsReportedOnceAndNamesBothEntries` (`:2335`) - so the claims they build state one
  protocol and one address, and verify the first still finds no row for a TCP and a UDP claim of one
  number and the second still produces one row over three claimants

## 7. Registration and documentation

- [ ] 7.1 Move this change's two spec files from `excused` to `accountable` in
  `tests/unit/coverage.nix`, the excuse expiring the moment a task here is ticked, and verify
  `testEverySpecificationIsClassified` and the scenario cross-walk are green: every scenario heading
  of both files finds the test name it derives
- [ ] 7.2 Update `docs/tooling.md`'s per-suite figures for `composition` and `plan` and the prose
  total, which this change moves by fourteen tests, and verify `testASuiteGainsATest` is green
- [ ] 7.3 Rewrite the claim row of `docs/authoring.md:142` as `{ proto, fixed, address }` with the
  domain, the range and the wildcard default stated, and add the three new identifiers to
  `docs/diagnostics.md:130` beside `port-claim-not-fixed`
- [ ] 7.4 Rewrite `docs/diagnostics.md:244`, which today states the protocol rule as though it were
  checked, over what the row now compares: the number, the protocol with an unstated one colliding
  with every protocol, and the address with an unstated one being the wildcard. Verify
  `nix build .#checks.x86_64-linux.treefmt` passes, vale included
- [ ] 7.5 Record the invariant in `CLAUDE.md` under Diagnostics, beside the paragraph about what two
  entries of one machine claim: the claim's three typed fields, why an unstated protocol is the wide
  reading and an unstated address is the wildcard, why a refused protocol or address widens the claim
  while a refused number drops it, and why neither reaches `alloc` or the entry key

## 8. Verification

- [ ] 8.1 Verify no golden moved: `nix eval --json .#debug.worked.plan | jq -S .` equals
  `fixtures/minimal-typed-edge/plan/*` as committed, and `diagnostics.txt` is byte-identical to the
  copy recorded in 1.2
- [ ] 8.2 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the fixture comparison and the `tests/unit/diagnostics.nix` cross-walks
- [ ] 8.3 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The
  claim index is evaluated per entry and both perf inputs claim one port per entry, so record the
  measured cost per entry at sizes 64 and 256 if the margin moved by more than half of the 0.15
  allowance
- [ ] 8.4 Run `nix run .#planner-e2e -- wired-pair shared-postgres` and verify neither folder
  regressed: both write a claim that loses its `count`, and `shared-postgres` is the folder that runs
  two clusters on one machine on two numbers
