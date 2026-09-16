## Context

See proposal.md - Why. The three shapes that decide the approach:

- **`unitVocabulary` is an attrset of korora types** (`lib/module.nix:58-70`), read against an
  allow-list, so adding a field is one line plus a type. `unitKeys` is `attrNames unitVocabulary ++
  [ "extends" ]` (`:72`), so nothing else enumerates the vocabulary.
- **`renderUnit` (`image/read.nix:484-529`) is the one renderer.** `flakelet/read.nix:166-171`
  delegates to it and appends an `[Install]` section, so a directive added there is emitted by both
  realisers by construction, and neither an image nor a flakelet unit can drift from the other.
- **`hostPathsOf` (`image/read.nix:217-232`) already distinguishes the dispositions.** It sets
  `disposition = if f.source != null then "source" else "render"` and hands each file a `from`. The
  change is what `from` is, not a new field: a `source` file's `from` is its own store path, a
  text-only `render`'s is the path the realiser assembled, and a `ref`-bearing `render`'s stays the
  staging path.

## Goals / Non-Goals

**Goals:**

- Make a crashed daemon restartable, with a policy the plan records and both realisers render.
- Narrow flakelet's configuration-file refusal to the files it genuinely cannot carry, so the
  store-backed tier stops being unusable for every server with a configuration file.
- Leave every deployment that exists today byte-identical: an entry that declares no restart policy
  and no configuration file must produce the same artifact and the same version digest as before.
- Close the one refusal whose own account says no row reports it.

**Non-Goals:**

- No further widening of the vocabulary. `Type=notify`, `ExecStartPre=`, socket units, `Group=`,
  `EnvironmentFile=` and ordering against a foreign unit stay out. Each is a separate decision with
  its own shape, and a restart policy is the one whose absence makes a working service into a broken
  one.
- No assemble step for flakelet. The realiser still runs nothing on the machine; what changes is
  which files need one.
- No change to the `[Install]` decision, to the profile denial table, or to how a secret reaches a
  unit. The second is `openspec/changes/open-a-delivered-value-to-its-reader`.
- No `reload` behaviour. `configData.<path>.reload` stays recorded and unacted-on here; acting on it
  is `openspec/changes/take-effect-on-a-second-apply`.

## Decisions

### `restart` is an enumerated atom, not a free string

A `restartPolicy` atom over `no`, `on-failure`, `on-abnormal` and `always`. Four values rather than
systemd's seven: `on-success`, `on-watchdog` and `on-abort` are either meaningless without a
`Type=`/`WatchdogSec=` this vocabulary does not carry, or a distinction only a caller already inside
systemd's model would draw. The atom is the planner's own domain, and a realiser maps it to its
service manager's spelling, so a launchd renderer answers `always` with `KeepAlive` rather than
being handed a systemd token.

Alternatives considered:

- **A boolean `restartOnFailure`.** Rejected: `always` is what a server wants and a boolean cannot
  say it, and a second boolean for that is two fields that contradict each other.
- **A passthrough string.** Rejected: the vocabulary is portable, and a passthrough makes every plan
  a systemd plan.

### The two contradiction rows, and the one shape that is not a contradiction

`oneShot` + `always` is a row: a unit that applies and exits successfully would be restarted for as
long as it keeps succeeding. `oneShot` + `on-failure` is not: a job that failed and may be retried is
a real shape, and refusing it would make the vocabulary opinionated where systemd is not.

`schedule` + any policy but `no` is a row because the timer is the schedule. A restart policy there
is a second schedule nobody declared, and the mistake is the same family as the one
`flakelet/read.nix:108-117` already prevents by giving a scheduled service no `[Install]`.

### A `source` file is shown from its own store path

The bytes are already a store object and the entry's closure already holds it. Staging it copies a
store path to `/run` to bind it back, which is work with no product. Under `image` the file is a
closure root of the entry, so it is inside the image; under flakelet it arrives with the artifact's
closure.

### A text-only `render` is assembled at build time, by the realiser

The plan holds the literals and hashes them (`contentHash`), so the assembled bytes are a pure
function of the plan. Each realiser writes them into a store path: `image` puts it in the image,
flakelet puts it in the artifact beside `units/`. The realiser rather than `lib/` does it, because
`lib/` realises nothing - `mkPlan` produces no derivation and no store path that is not a literal
string - and a file assembled in `lib/` would be exactly that.

Alternatives considered:

- **Assemble at attach time for `image` and refuse for flakelet.** Rejected: that is today's
  behaviour for `image` and the whole refusal for flakelet, and it leaves the store-backed tier
  unable to carry an nginx configuration for no reason that survives being written down.
- **Give flakelet an assemble step.** Rejected for this change: it needs a step the endpoint runs on
  the machine, which is a change to what flakelet is, and it is only needed by `ref`-bearing
  recipes. Those stay refused with a message that names the reference.

### The residual refusal names the reference, not the file's kind

`pathRule` becomes a statement about when the bytes exist, and the refusal names the `ref` that makes
them late. An author reading it can act: either the recipe's reference is really needed, and the
entry is realised as an image, or it is not, and the file becomes text-only and works.

### The unrendered-field row is read off the realiser's own table

`operator/read.nix` already mirrors the image reader's denial table
(`operator-entry-access-denied`), and the realiser sources reach that layer as arguments. The new row
asks the stated realiser for its directive table rather than restating it, so a directive added to
`image/read.nix` is a field the row stops naming with no edit in `operator/`. The refusal in
`image/read.nix` keeps its `throw` and gains the row id in its `accounts` entry, which is what
`tests/unit/diagnostics.nix` crosses.

## Risks / Trade-offs

- **A version digest moves for every entry that adopts a restart policy**, which is a redelivery. →
  That is correct: the unit file's bytes changed. An entry that declares nothing is unchanged, which
  the two "unchanged" scenarios pin.
- **`restart = "always"` on a unit whose command exits immediately is a restart loop the planner
  cannot see.** → Systemd's own answer is rate limiting, and the vocabulary carries no
  `StartLimitBurst`. Recorded as a known limit rather than guessed at; the contradiction rows cover
  the two cases a plan can actually detect.
- **Assembling literals in two realisers is the same logic twice.** → It is one helper in the shared
  reading (`image/read.nix` is what flakelet delegates to), so the assembly is written once and each
  realiser decides where the resulting path lives.
- **A `ref`-bearing recipe is still flakelet-refused, so the pincer on secrets-plus-config is only
  half opened.** → The other half is
  `openspec/changes/open-a-delivered-value-to-its-reader`: a unit that can read a delivered file
  directly usually needs no recipe that interpolates it.
- **Four restart values is a subset, and someone will want a fifth.** → The domain is stated in a row
  that names the four, so the refusal teaches rather than surprising, and widening the domain later
  is additive.
