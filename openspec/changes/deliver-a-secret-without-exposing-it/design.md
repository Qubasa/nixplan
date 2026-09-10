# Design

## D1 - Why the bytes go on standard input

A delivery has to move bytes the plan deliberately does not carry, to a path outside the store, on a
machine reached over one ssh connection. Four channels were available.

| Channel | Against |
| --- | --- |
| an element of the argument vector | what `cli/remote.py:125-145` does today: the plaintext is in `/proc/<pid>/cmdline` on the operator's host and in the remote shell's own arguments on the target |
| a temporary file on the machine, then a rename | the bytes still need a channel to reach that file, so the question is unanswered; and a dropped connection leaves a file at a path no plan names |
| a `nix copy` of an encrypted object | the machine then needs a key to open it, which is the same delivery one level down; the ciphertext rests in two stores until a collection, and `apply` installs nothing on a machine |
| the standard input of the remote command | chosen |

Standard input wins on one property the other three lack: the argument vector becomes a function of
the plan alone. The remote script names the path, the mode, and the owner, all three of which the
plan records, and reads the content from its own input. Both process tables can therefore be
observed and compared against a script the test builds itself (D8), which is a stronger claim than
"we looked and found nothing".

The costs are real and small. `Runner` grows an input channel, which means a step that writes bytes
and reads output has to hold both streams at once rather than calling `subprocess.run` twice. The
recording runner the pure tests use records the digest of the input rather than the input, otherwise
the recorder becomes the leak. And the script has to be fixed text: assembling it around the content
would put the content back into the argument vector by another route.

`nix copy --no-check-sigs` (`cli/remote.py:88-107`) stays. The artifact was built locally and signed
by nobody, so a signature check has nothing to check; what was missing is the authentication of the
machine receiving it, and that is D2. The copy travels the same verified channel as every other step
of the run, and the report names the options it used.

## D2 - What a host identity looks like in the registry, and a run with none

| Where an identity lives | Against |
| --- | --- |
| the caller's `NIX_SSHOPTS` or ssh configuration | today's answer: the identity is a property of the shell that launched the command, differs between two operators applying one deployment, and a test guest's accommodation arrives by the same route as a policy |
| a known-hosts file named on the command line | reviewable, but not versioned with the deployment, and two operators can hold two answers about one machine |
| a field of the machine registry, carried into the plan | chosen |

A machine record gains `hostKeys`, a list of public keys in the form ssh writes them. A list rather
than one key, because a machine legitimately presents more than one algorithm and because a rotation
overlaps: the old key and the new one are both correct for as long as the operator says. The plan's
`machine:<name>` entry records the list beside `address`, and the command writes the known-hosts
file of the run from the plan, then connects with verification demanded rather than inherited.

A run against a machine whose record states no identity is refused before the first dial, naming the
machine and the field. Verifying on first contact and recording the answer was the alternative, and
it loses on the case that matters: the first contact with a machine is the contact that carries the
first secret, so trust on first use grants exactly the window this change exists to close. It also
needs state the command owns, and the command owns none - `cli/manifest.py:118-127` builds with
`--no-link` and registers nothing.

Two arguments make an unstated identity a decision the invocation records rather than a default the
environment supplied. `--known-hosts <file>` names identities the operator holds by another route.
`--accept-new-host-key` accepts whatever answers, for a machine this run created and will destroy.
The end-to-end layer passes the second one, so the throwaway guest's accommodation is visible in the
argument vector the test issues and in the line the command prints, and an operator who reads their
own report can tell an unverified run from a verified one. The refusal is the command's rather than
the planner's because a build dials nothing: a deployment whose machines get addresses and
identities late is still a deployment worth building, which is the shape `lib/excluded.nix:23`
already records for `address`.

## D3 - Why the identity is outside the hashed machine record

`machineKey` is `shortHash (toJSON record)` over the whole machine record (`lib/plan.nix:25`,
`:713`, `:780`), a service entry names `machine:<name>@<key>` in `dependsOn`, and `CLAUDE.md`
records that the machine fact reaches a placement's key only through `dependsOn`. A `hostKeys` field
inside the hashed record would therefore move every entry key of that machine whenever an identity
rotates, and every artifact would be rebuilt for a fact no unit renders from and no image contains.

Hashing it and accepting the re-key was the alternative. It loses because a rotation is an
operational event about reaching a machine, not a change to what the machine runs, and this
repository already draws that line twice: an image's version digest is deliberately not the entry
key, and the delivery set of a generated value is deliberately not in the value's key.

The mechanics are therefore that `machineKey` hashes the record without `hostKeys`, and the plan
entry records the field beside the key. The claim a suite can hold is the observable one: rotate an
identity, and no key in the plan moves.

## D4 - The mode and the owner of a delivered file

`cli/remote.py:140-145` writes `0400` owned by the login user, and the plan has nothing else to
offer: the value-file record (`lib/plan.nix:89-99`) carries `path`, `secrecy`, and `inPlan`. The
question is how a delivery learns a mode and an owner without the plan acquiring a notion of users,
which it has refused twice (`lib/resolve.nix:42-48` has no machine class, and
`deliver-secrets-across-machines` deferred `files.<n>.owner` for that reason).

| How the owner is stated | Against |
| --- | --- |
| a user name | a bare name is a fact about one machine's password database, which the plan cannot check and a delivery set spans |
| a numeric identifier | worse: the number differs between two machines of one delivery set |
| `"root"`, or a reference to a unit the plan carries | chosen |

The reference resolves through a field the plan already holds. `units.<u>.user` is the field
`image/read.nix:301` reads for `needsStaticUser`, so a file declaring
`owner = { unit = "worker"; }` is answered by that unit's own `user`, and the plan learns which unit
answers for a file rather than learning about users. A reference to a unit that declares no `user`,
or to a unit of an entry no machine of the delivery set runs, is an error row. `mode` is a
four-digit string, the vocabulary a configuration file's `mode` already uses, which is why
`config-file-mode-missing` exists.

Both fields are recorded whether or not an author wrote either, defaulting to `0400` and `"root"` -
today's behaviour, written down. That follows the rule `CLAUDE.md` states for `delivery` and
`deliveryDerivedFrom`: a reader must not be able to mistake the field for an absence.

The field pays for itself through one check. A unit that opens the path of a generated file is a
mention site the planner already walks (`lib/plan.nix:344-390`), and a unit whose declared `user` is
not the recorded owner, against a mode granting nothing to group or other, cannot read what was
delivered for it. That is string equality on names plus two digits of a mode, and no user database.
The failure it catches is the silent one from C5: on the default realiser the combination renders
`User=<name>` and the unit fails at run time with a permission error nobody predicted.

## D5 - A denial per unit, and the combination this change still refuses

`image/read.nix:301-318` computes `needsRootOnlyFile` from the entry's own secret generated files
and then maps each one across `attrNames units`, so one root-only file refuses every unit of the
entry. An entry that owns a secret and runs a second unit that never reads it cannot be confined at
all.

The denial names the units that name the file. The alternative was to keep the entry-level denial
and tell an author to split the entry, which loses badly: an entry is a member's placement, so
splitting it renames units, moves keys, and produces a second artifact, all to express a
confinement.

What stays refused is the unit that both names a root-only file and runs under a profile carrying
`DynamicUser=yes`, which is every profile except `trusted` (`image/read.nix:41-55`). Its user
identity does not exist until it starts, so no owner a delivery could write would admit it. Closing
that needs a credential the service manager opens as root before the unit's namespace exists; its
shape is a plan field naming the credential beside the file it comes from, a rendering of that field
in each realiser, and a profile table that stops denying a root-only file to a unit naming it as a
credential rather than as a path. The proposal defers it, because designing a second delivery
mechanism before the first one stops leaking is the wrong order.

The build-time raise for a denial is second, not first. `report-every-refusal-as-a-row` gives the
condition a row from the deployment build under its requirement "A confinement profile is checked
against the entry it confines", because a profile is a fact of the realisation statement rather than
of the plan. This change decides which units that row names.

## D6 - A row names two types and never the value

Three rows interpolate korora's message (`lib/module.nix:655-664`, `lib/resolve.nix:822-830`,
`lib/interface.nix:264-273`), and korora prints the value:
`Expected type 'int' but value '"hunter2-db-password"' is of type 'string'`, evaluated against the
pinned revision. The same rows tell the reader the failing value is not recorded.

| What the evidence carries | Against |
| --- | --- |
| korora's message | prints the value into a table that reaches a terminal, a log, and a store file |
| the value truncated or digested | a prefix of a secret is a leak of a prefix, and a digest is not a fact an author can act on |
| the type declared, the type received, and the shape of the value | chosen |

The shape is the size of the value in the terms of its own type: the length of a string or a list,
the key names of an attribute set. Those are structure an author wrote in a Nix file, never bytes a
generator produced, and they are what tells "the wrong field" apart from "the right field, wrong
type".

The library keeps calling `verify` and reads the type names from the atom's own `type.name` and from
`builtins.typeOf`, rather than parsing korora's string. Parsing a message for data would make the
row's text a function of an upstream revision, and the table is compared byte for byte against
`fixtures/minimal-typed-edge/plan/diagnostics.txt`.

The property that falls out is worth stating on its own: the row text becomes a function of the
declared type and the received type, so two different wrong values of one type render one table, and
editing a fixture's offending value leaves the golden file untouched.

## D7 - A mount point for every generated file a unit names

An image is the root a portable service runs with, so a path its unit names has to exist inside it.
`image/read.nix:228-242` builds those mount points from `entry.vars`, filtered to the files the
plan records as a reference, which is the entry's own generators and the secret ones alone.

| Source of the host paths | Against |
| --- | --- |
| the entry's own secret generated files | today: misses every value the entry reads rather than owns, and every public file delivered to it |
| every value entry of the plan | mounts files the entry has no business seeing, and the host path list enters the image's version digest, so an unrelated value would rebuild the image |
| the generated paths the entry's units, configuration files, and resolved reads name | chosen |

The walk already exists twice. `referencePaths` (`image/read.nix:220-226`) collects the `ref` items
of a configuration file's render list, and `mentionSites` (`lib/plan.nix:344-390`) is the planner's
own enumeration of every place an entry names a string. The image reader performs the same walk over
the entry it was handed, and every generated path it finds gets a mount point, whether the entry
owns the generator or read it, and whether the file is secret or public.

A generated path a unit names that no value entry of the plan accounts for fails the build naming
the entry, the unit, and the path. Under the rule `report-every-refusal-as-a-row` owns, that raise
follows a row: `vars-not-deployed-opened` and `slot-reads-undeployed-value` already cover a path
whose value reaches no machine, and the remaining case - a path that matches no value entry at all -
is a plan fact and therefore `mkPlan`'s row.

A consumer image's version digest moves as a result, which is the correct answer rather than a cost:
the image now carries a mount point it did not carry before.

## D8 - Observing a process table without the observation becoming the leak

The machine layer has to prove a negative about a window that is milliseconds long, on two hosts,
about bytes it must not print.

| Observation | Against |
| --- | --- |
| search `/proc/*/cmdline` for the bytes while the write happens | the needle is the secret, so the sampler's own arguments carry it, and a failure message prints it |
| capture the process table to a file and search afterwards | the captured file is the leak the test came to look for, and it rests in the run's state directory |
| record each process as its command name and the digest of its argument vector, and compare against the digest the plan implies | chosen |

The comparison is possible because D1 made the remote command a function of the plan: the path, the
mode, and the owner are plan facts, and the script's text is specified, so the test builds the
expected argument vector itself and holds the observation to its digest. A smuggled byte changes the
digest, and the failure names two digests. The sampler searches for nothing, so it carries no
needle.

The operator's end needs no sampler. The argument vector the command runs is a function of its
inputs, which is what `tests/e2e/test_harness.py` already asserts about ordering, and the recording
runner records the digest of the input stream instead of the stream.

The target's journal is the third place to look, and the same discipline applies: sshd records the
command it ran and not what was written to its standard input, which is the property the channel was
chosen for, so the assertion reads a count of matches in the session's journal and never a match.

Timing is handled by the sampler being a unit started before the deliver phase and stopped after it,
so the window is covered rather than guessed at. `--retry` and `wait_until_succeeds` exist in this
layer for cross-machine boot ordering, and using them here would make an observation into a poll.

## D9 - What the value source check inspects, and what it declines to

`cli/values.py:85-123` refuses a source that is not a directory, a declared file the source lacks,
and a file no value declares, and inspects nothing about how the bytes rest. `held()` selects with
`rglob("*")` and `is_file()`, which follows a link out of the source. `ValueFile.secrecy` is parsed
at `cli/manifest.py:38-43` and read nowhere in `cli/`, which is the whole finding: the one program
that knows those bytes are secret treats them as bytes.

Checked, for a file whose value entry declares it secret: the entry is a regular file rather than a
link, the invoking user owns it, its mode grants nothing to group or other, and every directory from
the source root down to it satisfies the same. A public file gets none of that, because its bytes
are in the plan already.

Declined, and each for a reason:

- **ownership by root.** An operator's own value directory is the ordinary case, and demanding root
  would push every run through a privileged copy.
- **an encrypted-at-rest property.** Where the bytes come from is the store's business; the command
  reads a directory and cannot tell a decrypted export from a hand-typed file.
- **an access control list.** Not portable across the filesystems an operator may hold a source on,
  and the mode bits already answer the question the check is asking.

Refusing rather than warning, because the run is about to publish those bytes to machines, and a
warning printed before a successful apply is a warning nobody reads. The refusal happens where the
other source refusals already happen, before the first dial, so an operator fixes a directory rather
than a half-applied deployment.
