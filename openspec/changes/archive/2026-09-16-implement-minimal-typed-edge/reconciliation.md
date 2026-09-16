# Fixture reconciliation

`fixtures/minimal-typed-edge/plan/backup.json` was written by hand before
anything ran. This is the field-by-field comparison between it and the first
plan the library produced for
`fixtures/minimal-typed-edge/deployment/`, with every difference sorted
into one of three buckets and none left unclassified.

The comparison excludes the prose fields the fixture carries for a reader
(`note`, `why`) by an explicit key list rather than a heuristic, so adding a
note to the fixture cannot silently weaken the golden test.

Method: `nix eval --json .#planner.worked.plan` against the committed file,
flattened to leaf paths. 29 fields present only in the committed file, 102
present only in the generated one, 13 present in both with different values.

## A. Placeholder the fixture never claimed to be real

Each of these is a value the hand-written file shortened or invented. The
generated value replaces it.

| Field | Committed | Generated |
| --- | --- | --- |
| `<entry>.key` (3 entries) | `sha256-a41e07d2`, `sha256-1d90b7fe`, `sha256-c7fa2e50` | a real 16-hex truncation of a sha256 over the entry's hashed inputs |
| `<entry>.dependsOn[0]` (3 entries) | `machine:vault@sha256-3f10cc84` and two more | the machine entry's own computed key |
| `<entry>.closure` (3 entries) | `/nix/store/8m2c...-borgbackup-1.4.0` | the fixture's literal store path strings, unshortened |
| `nightly:client@*.env.BORG_RSH` (2 entries) | `/nix/store/qk44...-openssh-9.8p1/bin/ssh -i …` | the same string with the real store path |
| `vault-repo:server@vault.reads.clients.entries.*.publicKey` (2 entries) | `ssh-ed25519 AAAAC3Nz...alpha` | a full ed25519 public key, deterministic per machine |
| `vault-repo:server@vault.configData."/srv/borg/.ssh/authorized_keys"` | `sha256-incomplete` | `contentHash = null` with `computed = false` |

## B. Correction to the folder

The generated value is right and the committed file is wrong. Nine of these are
absences: a hand-written file elides what an evaluator has to produce.

1. **The fixture is missing five entries, not two.** It writes three, names two
   as elided, and the deployment produces eight: four placements
   (`vault-repo:server@vault`, `nightly:client@{alpha,beta,gamma}`) and four
   machine entries (`machine:{vault,alpha,beta,gamma}`). Its own `dependsOn`
   fields name `machine:vault`, `machine:alpha` and `machine:gamma`, none of
   which it contains, which is what `specs/planner/plan-artifact/` refuses in
   *The fixture elides nothing*: a fixture may not reference an entry it does
   not itself hold. `tasks.md` 8.1 says "five entries, one per placement"; that
   count is the hand-written file's own arithmetic (three written plus two
   elided) and it is wrong in both halves — there are four placements, and the
   machine entries the plan needs bring the total to eight.
2. **`declaringFile` is relative to the deployment root**, `interfaces/default.nix`
   rather than `../interfaces/default.nix`. The committed value is relative to
   `plan/`, which makes a plan's contents depend on where the plan file happens
   to sit. `plan/diagnostics.txt` already states the root-relative convention
   for row subjects, and the library applies it to the plan too.
3. **Export records are nested under `exports`** instead of sitting beside
   `interface`, `declaringFile` and `keysetEqualsInterface`. In the committed
   shape an interface declaring an export named `interface` would overwrite the
   interface name, and the keyset rule guarantees nothing about export names.
4. **`configData` is keyed by file and each file carries a record**
   (`contentHash`, `computed`, `reload`, and `row` when it is not computed).
   The committed shape puts `reload` beside the file paths, so a service
   rendering a file called `reload` would collide with it.
5. **`closure` is a list of store path roots.** The committed value is one
   string naming borgbackup, while the same entry's `env` interpolates openssh:
   the client's closure is two paths and a single string cannot hold both.
6. **A `row` reference is a record**, `{ id, subject }`, not the prose string
   `vault-repo:server@vault authorized set`. A test can resolve a record
   against the diagnostics table; a sentence it cannot.
7. **`units` are recorded.** The committed file has none, yet its own
   `configData.reload` names `borgRepo`. A plan with no units cannot be
   applied, so each entry carries `units.<name>.command`.
8. **`settings` are recorded on every entry**, with the source of each resolved
   value. The committed file carries them on the server entry only.
9. **A single-valued read records the values it received** under
   `reads.<slot>.values`, and every read records `delivered`. The reader's key
   hashes what it read, so a plan that does not record it cannot be reviewed
   against its own key.
10. **`generation: 3` is dropped.** The library emits no plan-level generation
    counter; nothing in `specs/planner/plan-artifact/` describes one, and a
    hand-maintained number in a generated file is a placeholder by another
    name.
11. **The two row messages in `plan/diagnostics.txt` were hand-written
    English.** The committed rows read `authorized set names three entries and
    one has no bytes` and `the authorized set is in this entry's key`; the
    library names the slot the module declared and the entry that has no
    bytes, `clients names three entries and `nightly:client@gamma` has no
    bytes`. Subject and severity already matched. Both message lines are
    replaced, and the prose blocks under them - evidence, effect, why row - are
    untouched, because none of them was wrong. `suites/golden.nix` parses the
    committed file for its `!` rows and compares subject, severity and message,
    so the file cannot drift from the library again without a red test.
12. **Prose sits on entries, never beside them.** The hand-written file put a
    `note` beside the file paths of `configData` and beside the export records
    of a capability, where a file or an export of that name would collide with
    it. Each moved onto the record it is about. The top-level `note` stays at
    the top level, and the golden comparison excludes `note` and `why` by name
    at every depth.

## C. Defect in the library

1. **An absent export did not name the row its absence produced.**
   `specs/planner/plan-artifact/` requires that the plan "record the export
   with a null value and an explicit marker that its bytes are absent, and name
   the row the absence produced", and the committed fixture does exactly that on
   `nightly:client@gamma.provides.identity.publicKey.row`. The first generated
   plan carried the marker and the null value but named no row. Fixed in
   `lib/plan.nix`: an absent export records `rows`, one reference
   per reading entry, so a null value in the plan leads to the refusal instead
   of standing beside it. The fixture's singular `row` becomes `rows`, because
   an export may be read by more than one entry.
2. **Every row produced at an unplaced member was dropped from the table.**
   Found while writing the plan suite rather than by this comparison, because
   the deployment in this folder places every service. `resolve.nix` collected
   rows from `member.rows` and from each placed placement and never from the
   unplaced one, while `plan.nix` still emitted the unplaced entry. An instance
   no placement selected whose module publishes the wrong keyset therefore
   produced a plan recording `keysetEqualsInterface = false` beside an empty
   diagnostics table, which is the silence `specs/planner/diagnostics/`
   forbids. `module-raised` and `export-type-mismatch` were swallowed the same
   way. Fixed in `lib/resolve.nix`: a member with no placements
   contributes its unplaced rows, and `mkCapability` takes the entry key rather
   than rebuilding it from a machine that is null at that placement.
3. **A row counted one entry in the plural**, `dep names one entries and
   `p:only@one` has no bytes`. `util.countNoun` agrees the noun with the count
   at the three sites that render one.

Re-run after the fixes: the defect bucket is empty. Every remaining difference
is in bucket A or bucket B, and both are answered by replacing the fixture.

## Checked, and not a defect

An absent value read through `reach = "one"` does produce a row. The absence
rows are built per resolved entry rather than per arity, so a single-valued
read of an export that was declared and never published yields
`set-entry-absent` against the reading entry exactly as a set does, and the
provider's export record names it. Probed directly rather than argued, because
the folder's own deployment reads a set and no suite scenario crosses a
single-valued read with an absent value.
