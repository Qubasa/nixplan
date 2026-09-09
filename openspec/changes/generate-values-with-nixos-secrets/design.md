## Context

See [proposal.md](proposal.md) for motivation. What shapes the approach is the external contract,
read at nixpkgs PR #547171 head `e6af758a5745ac4adef763deb0f1771cec58c461`, whose
`pkgs/by-name/ni/nixos-secrets/src/nixos_secrets/secrets-config.schema.json` is the authority. Four
facts of that schema decide most of this design.

1. **A `SecretsConfiguration` needs no NixOS configuration.** `_type = "secrets-configuration"`
   makes the CLI treat the object as final, and `--json` hands one in without evaluating Nix at all.
   The module system, `jsonify.nix` and `eval.py` are all bypassable.
2. **The schema carries no path.** `store.<name>.files.<f>` requires exactly one key, `deploy`, a
   boolean. `path` exists only as a NixOS option (`fileModule` in
   `nixos/modules/security/secrets/default.nix`), set by a backend, and a configuration that never
   goes through the module system therefore has no path anywhere in it.
3. **`deploy.remote` has no target.** It is given a file list "in the same format used by `list`",
   and its own description says any further information "can be provided by the user through
   environment variables". There is no machine, address or recipient in the contract.
4. **`safe-name` is `^[a-zA-Z0-9:_\.-]+$`.** A colon is admitted; `/` and `@` are not. So a plan key
   `<instance>:vars/<gen>@<machine>` is not a name, and a colon-joined projection is.

Every one of the four was read at that revision and each is verifiable in a local checkout of it:
the five required store keys, the single required file key `deploy`, the anchored `safe-name`, and
`generate` as a nullable store derivation path. The schema file at that revision is
`sha256:44408bcdca7e59af6f9f05e4fe30ef6aa6df004f97e3df68d8e8d2062a4876cf`, which is the value the
guard of D7 compares against.

One fact of this library matters as well. `lib/resolve.nix:571` already sets a secret file's
`content` to `null` unconditionally, so the purity this change has to add is a property of the
*process* that fills `varsState`, not of the plan.

## Goals / Non-Goals

**Goals:**

- One plan, read into a configuration the external CLI runs against, with the machine dimension
  supplied by this library and nothing else changed upstream.
- The bytes of a generated value produced by a real generator and stored by a real backend, with the
  existing delivery-set assertions unchanged, so a pass means the composition works rather than that
  a new test was written.
- Every failure of the composition named at its cause: a colliding name, an unaddressable machine, a
  stale stored value.

**Non-Goals:**

- Fixing the upstream rollback and staleness gap. This change *detects* it and refuses; it does not
  make the external tool transactional.
- A production store backend. The end-to-end folder uses the PR's own example `age` backend.
- Prompts. The library has no prompt vocabulary, so a store entry's `prompts` is always `{}`. A
  deployment needing an interactive value cannot be expressed, and that is a refusal by the rule
  that a required field the plan cannot answer is named rather than defaulted.
- Any change to how the planner *resolves* anything. It gains one declared field and one entry
  field, both inert: recorded, never run, never read. It does not learn that a backend exists.

## Decisions

### D1. Emit the JSON object, not a NixOS module

`secrets/read.nix` produces the `SecretsConfiguration` directly and the driver passes it with
`--json`.

*Alternative:* render a NixOS configuration and invoke the CLI with `--file` or `--flake`. Rejected
on two grounds. It would make the library depend on the NixOS module system, which it does not today
and whose global fix point is the thing the library exists to avoid. And it walks straight into
review comment `r3820972963`: under `--file` the configuration evaluates with
`networking.hostName` at its default, under `--flake` it gets the real one, and the example backends
key their storage path on it - the same declaration then reads and writes two different locations.
A `--json` configuration has no `networking.hostName` to disagree about.

### D2. Render `deploy.remote` from the plan

`secrets/backend.nix` renders one script that carries, per projected name and file, the machines of
the value's delivery set, the address the plan records for each, and the path the plan fixed. The
CLI is invoked once, for the whole cluster.

*Alternative A:* invoke the CLI once per machine with a per-machine configuration. Rejected: each
invocation's `list` output then describes only that machine's values, and the schema's own note says
`collect-garbage` deletes anything `list` reports that the configuration does not carry - so
per-machine invocation makes review comment `r3820900132` reachable from a second direction, with
one machine's run able to delete another's stored values.

*Alternative B:* propose a per-file recipient set upstream first. Rejected as a prerequisite, not as
an idea: it blocks the whole change on a review cycle, and rendering the script proves the shape
that such a field would formalise. Kept as an open question.

### D3. The projection is colon-joined, injective, and refuses

`<instance>:<gen>` for a per-instance value, `<instance>:<gen>:<machine>` for a per-machine one. A
component containing a colon, a component containing a character outside `safe-name`, and two keys
landing on one name are each an error naming both sides.

*Alternative:* project onto `util.shortHash` of the key. Rejected: these names are what an operator
sees in `list` output, in a backend's storage layout and in a GC prompt about deleting something. A
hash makes every one of those unattributable, and the collision the projection has to avoid is
exactly the case where two instances' secrets would be confused - which a hash hides rather than
prevents.

### D4. The path stays this library's

Because of context fact 2 the configuration cannot carry a path, and because of D2 the deploy script
is ours, so the path the plan fixed (`/run/vars/<instance>/<gen>/<file>`) reaches the machine
through the script and through nothing else. The external side never learns a path and never has to
agree about one. This also keeps `fileModule` unused, which is what lets the configuration skip the
module system at all.

### D5. Provenance lives in the driver, not in the plan

The driver writes, beside the state it read, the plan entry's own key for each stored value, and
compares before delivering. A disagreement, or an absent record, refuses the run.

*Alternative:* a `varsState.<key>.from` field and a `vars-state-stale` diagnostics row. Rejected.
Staleness is a fact about bytes on disk, which the library cannot observe; the row would be the
planner restating a claim its caller made, and the repository already carries exactly one such
field - `pin`, "recorded, never verified" - which is a licence for one, not a pattern to extend.
Keeping it in the driver also means the identity compared is the plan key the planner already
computes over the declaration, so nothing new has to be hashed.

This is the concrete answer to review comment `r3821143332`: the CLI cannot tell a stale derived
value from a current one because it records no provenance, and a plan key *is* provenance over the
declaration, computed totally at evaluation.

### D6. The tool is resolved at run time, not pinned as an input

`$NIXOS_SECRETS_FLAKE` defaults to the fork and revision above and is resolved with `--refresh`,
exactly as `tests/e2e/runner.py:resolve_rookery` resolves rookery and for the same reason: a branch
reference otherwise resolves through nix's tarball TTL and a run silently uses whatever was fetched
last. An unresolvable reference skips the folder with a reason, which `pytest.ini`'s `-rs` prints.

*Alternative:* a flake input. Rejected by the library's stated goal of carrying no hard-coded flake
dependency, and because the reference is an unmerged branch of a fork: pinning it in `flake.lock`
would make every consumer of this repository fetch it.

### D7. The guard fails loudly and never spuriously

The digest recorded in Context is compared against the digest of the `secrets-config.schema.json`
the resolved tool carries. A difference fails the check, naming `secrets/read.nix`, the recorded
revision and the upstream path to diff. A digest rather than a committed copy, because a copy of
another repository's file is a second thing to keep current and this repository's own rule is that
a citation states the fact it cites; the fact here is "this contract, unchanged".

An unresolvable tool does not fail the check - an unreadable signal is not evidence the contract
moved - and the run that needed the tool skips instead.

### D8. `secrets/` is the realiser, `vars` is the existing suite's new name

The suite of a realiser is named after its directory (`image`, `flakelet`), so the new suite has to
be `secrets` and the existing `secrets` suite - which is about `vars.<gen>` declarations and vars
entries - becomes `vars`. That is the name it should have had: it tests the plan's vocabulary, not
an external tool. The rename touches `tests/default.nix`, `tests/unit/coverage.nix` and the suite
table in `docs/tooling.md`, and is a clean cutover with no alias.

### D9. The end-to-end folder uses the PR's example `age` backend

It is explicitly not production-ready, and its storage path is global and keyed on the host name.
The folder points it at the run's own state root, so two runs cannot collide, and never invokes
`collect-garbage`, so the deletion hazard is unreachable. What the folder proves is the composition,
not the backend.

### D10. The generator's program is a plan field, and not a closure root

`generatorKeys` is `files`, `per`, `deploy`, `reads` (`lib/module.nix:118-123`), and a vars entry
of the worked plan carries `delivery`, `deliveryDerivedFrom`, `dependsOn`, `deploy`, `files`,
`key`, `per`. Nothing anywhere says how a value's bytes come to exist, and the external contract
requires one store derivation per store entry. So the field has to be added; the only questions
are where it lives and what it is.

*It lives in the plan*, not in an argument the realiser is handed beside the plan. `image/read.nix`
and `flakelet/read.nix` each read a plan and nothing else, and that is what makes an artifact a
function of the plan a reviewer read. A side table would make the generator invisible to the
plan's own diagnostics and to every reader that is not this one.

*It is a store path recorded as a literal string*, like every other store path in a plan, and the
planner neither runs nor reads it. The external contract wants a `.drv` specifically
(`^/nix/store/.+\.drv$`); a deployment therefore declares `drvPath` rather than an output path,
which is expressible in a pure evaluation and is still just a string.

*It is exempt from the closure scan.* `lib/plan.nix` holds every store path an entry mentions
against that entry's declared closure, because a closure is what a machine is given. A generator
runs where the plan is read - on the machine holding the values, never on one receiving them - so
making it a root would ship every deployment's generators to every machine that receives one of
their outputs, and leaving it unexempted would make declaring a program an error row.

*Omitting it stays valid.* Every deployment in this repository declares no program, the worked
fixture continues to declare none, and the golden plan is therefore unchanged. The refusal for a
missing program lives in the reader that needs one, which is what
`realiser/secrets-configuration` already requires of a field the plan cannot answer.

## Risks / Trade-offs

- **The external API is under review and will move.** → D7's guard, plus a recorded revision. A
  merged-and-renamed API fails the check with the file to edit named, rather than a reading that
  silently describes a contract nobody publishes.
- **The example backend's global, host-name-keyed path.** → D9: the run's state root, and no GC. The
  hazard is recorded here with its review comment rather than worked around silently.
- **`bubblewrap` needs user namespaces the sandbox may not have** (review comment `r3821015145`, a
  hard crash with no message). → The driver probes the sandbox once and skips the folder with a
  reason naming the missing kernel feature, the same shape as an unresolvable tool.
- **A prompt would hang the run** (review comments `r3821062507`, `r3821148209`: a swallowed
  question, and terminal echo left off after a crash). → The configuration declares a prompt backend
  that fails on any invocation. Nothing this library can express needs a prompt, so a prompt being
  asked at all is a bug, and it becomes a named failure instead of a wedged run.
- **A new end-to-end folder is a new snapshot cut, about 2 GiB per machine, never evicted.** →
  Three machines, one cut, and the folder documents `rookery snapshot gc --all` as the only reclaim,
  as the existing folders do.
- **The staleness refusal is conservative: it can refuse a run an operator believes is fine.** →
  Accepted deliberately. The failure it replaces is a stale credential reported as a success, and
  the refusal names both identities so the operator can regenerate the one value it names.

## Migration Plan

Nothing deployed changes. The suite rename (D8) is internal to the test tree and is applied in one
commit with its registration points. The new folder is additive: `nix run .#planner-e2e` gains a
third folder name and the other two are unaffected.

## Open Questions

- Whether to propose a per-file recipient set upstream (D2, alternative B) once the rendered deploy
  script exists as evidence of the shape. Deferrable: it changes no spec here, and the rendered
  script is what a proposal would be argued from.
- Whether the provenance record (D5) is worth offering upstream as the metadata blob the PR author
  sketched on 22 Aug. Deferrable for the same reason: this change produces the identity either way.
