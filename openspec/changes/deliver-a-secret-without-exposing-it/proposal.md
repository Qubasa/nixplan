## Why

The design promises that a secret's bytes are in no plan and in no artifact, and the apply that
moves them breaks the promise twice over.

`cli/remote.py:125-145` base64-encodes a value's bytes into a shell script, and
`cli/apply.py:206-218` hands that script to `ssh` as one element of an argument vector. The
plaintext is therefore in `/proc/<pid>/cmdline` for every local user on the operator's host, and, as
the remote shell's own arguments, for every local user on the target, before it reaches the `0400`
file the script ends with. That path is the only delivery mechanism for every secret the library
manages. `cli/remote.py:51-53` then runs each step with `check=True`, and `cli/planner.py:150-153`
catches `ApplyError` alone, so the `CalledProcessError` raised by a target whose `/run` refuses a
write renders that same argument vector into stderr and into any log that captured it.

A run cannot tell the machine it means from whatever answers at the address.
`lib/resolve.nix:42-48` lists the five fields a machine registry record may carry - `address`,
`tags`, `system`, `serviceManager`, and `microarchitecture` - and none of them is an identity, so a
deployment cannot state one. `cli/remote.py:60-79` adds `-i` to whatever `NIX_SSHOPTS` already held,
and `tests/e2e/delivery.py:194-206` sends the throwaway guest's `StrictHostKeyChecking=no` and
`UserKnownHostsFile=/dev/null` through that same variable. An operator whose shell still exports it
writes secrets to whatever answers, and the command prints nothing about the options it connected
with.

Three smaller gaps sit on the same subject:

- **The mode and the owner of a delivered file are the command's constants.**
  `cli/remote.py:140-145` writes `0400` owned by the login user, and the value-file record at
  `lib/plan.nix:89-99` carries `path`, `secrecy`, and `inPlan`, with no field a delivery could
  read instead. A unit that declares `user` therefore cannot read the secret delivered for it.
  `image/read.nix:301-318` refuses that combination under a confining profile; flakelet reads with
  `trusted`, whose `denies` list is empty (`image/read.nix:53`), so the default realiser renders
  `User=<name>` and the same combination passes.
- **A row prints the value it refuses.** `lib/module.nix:655-664`, `lib/resolve.nix:822-830`, and
  `lib/interface.nix:264-273` interpolate korora's message into a row's evidence. Evaluated against
  the pinned korora, that message reads
  `Expected type 'int' but value '"hunter2-db-password"' is of type 'string'`, while the same row's
  resolution says the failing value is not recorded, as does `docs/diagnostics.md:109`. A mistyped
  secret export prints its bytes into the table, which reaches a terminal, a log, and for a
  warning-severity row a world-readable store file.
- **An image carries no mount point for a value it did not generate.**
  `image/read.nix:228-242` derives the host paths of generated files from `entry.vars`, the entry's
  own generators, filtered to those the plan records as a reference. A consumer that reads another
  instance's secret has no such record, and a delivered public file is filtered out, so
  `image/default.nix:96-99` creates no file and the rendered unit gets no `BindReadOnlyPaths`. A
  portable service runs with the image as its root, so the path its own environment names does not
  exist inside it, and neither realiser refuses it.

What an operator hits is a working apply that leaked. The one end-to-end assertion about a delivered
secret, `tests/e2e/secret-delivery/test_secret_delivery.py:279-283`, reads the file's mode and owner
and searches every artifact, and reads no process table on either end.

## What Changes

- **A value's bytes travel on the remote command's standard input.** `write_script` stops carrying
  content. The remote script names the path, the mode, and the owner, and reads the bytes from
  standard input, so the argument vector on both hosts is a function of the plan alone. `Runner`
  gains an input channel, and the recording runner the pure tests use records the digest of that
  input rather than the input.
- **A failed remote step is reported by what it was, not by how it was spelled.** Every step the
  command runs on a machine reports the step, the machine, the exit status, and the machine's own
  error output. No refusal, no traceback, and no log line carries an argument vector or the bytes of
  a value.
- **The machine registry states a host identity.** `machineRegistryKeys` gains one field, the plan's
  `machine:<name>` entry records it, and the command builds the known-hosts file of the run from the
  plan rather than from the caller's environment. The field is outside the hashed machine record, so
  rotating an identity moves no entry key and rebuilds no artifact (D3).
- **The command states the options it connects with, and reports them.** `NIX_SSHOPTS` stops being
  an input to the connection: what a run uses comes from the plan plus explicit arguments, and the
  first line of an apply names them. A throwaway guest's accommodation is one of those arguments,
  visible in the invocation the test issues.
- **A machine with no stated identity is refused before the first dial.** The refusal is the
  command's, not the planner's, because a build dials nothing and must stay buildable for a machine
  whose address and identity are assigned late (`lib/excluded.nix:23`).
- **A generated file declares the mode and the owner it lands with.** A file declaration takes
  `mode` and `owner` beside `secrecy` (`lib/module.nix:352-361`), and the value-file record carries
  both whether or not the author wrote either. `owner` is `"root"` or a reference to a unit the plan
  carries, whose own `user` field answers it, so the plan gains no notion of users it does not
  already have (D4). A unit that opens a file the recorded mode and owner do not let it read is an
  error row.
- **A refused secret export carries no bytes.** `lib/resolve.nix:799` sets the export's `value`
  before `export-secret-not-a-reference` is decided, and `lib/plan.nix:171-174` copies it into the
  plan, so a direct `mkPlan` consumer receives the bytes the row complains about. The record omits
  the value for an export that refusal names.
- **A row states the type it expected and the type it received.** The three rows that interpolate
  korora's message state two type names and the shape of the offending value, and never the value.
  The row text becomes a function of the types, so two wrong values of one type render one table.
- **An image carries a mount point for every generated file its units name.** The host paths of an
  image are derived from the paths the entry's units, configuration files, and resolved reads
  actually name, whether the entry owns the generator or reads it, and whether the file is secret or
  public. A generated path a unit names that no value of the plan accounts for fails the build
  naming the entry, the unit, and the path.
- **Confinement is denied per unit.** `image/read.nix:301-318` maps a root-only file onto
  `attrNames units`, so one unit's need refuses the whole entry. The denial names the units that
  name the file, which is what lets an entry own a secret and confine the units that do not read it.
- **The machine layer proves the negative.** While a value is delivered, its bytes appear in no
  process table on either host and in no journal on the target, and the observation compares digests
  the test computed from the plan so that a failure names a mismatch rather than a value (D8).

Not in this change, deliberately:

- **Secrecy on a setting or on a unit environment value (C8, second half).** `settings.defaults` and
  `settings.fixed` take a plain value (`lib/module.nix:114-116`), the settings record copies it
  verbatim (`lib/plan.nix:334-339`), and a unit's `env` is rendered into the unit file inside the
  image (`image/read.nix:390-394`). Marking either secret would be a promise this change cannot
  keep: the only channel that moves bytes outside the plan is a generated file, so a secret setting
  would have to become a value entry, and then the declaration that names it is a read rather than a
  literal. The change that adds `secrecy` to a settings declaration is the change that gives a
  setting a delivery, and until then the honest expression of a secret setting is a generator and a
  declared read.
- **A credential channel for a confined unit that reads a secret (part of C6).** After this change
  an entry may own a secret and confine the units that do not name it, and a unit that both names a
  root-only file and runs under a profile carrying `DynamicUser=yes` is still refused, because its
  user identity does not exist until it starts. Closing that needs a credential the service manager
  reads as root before the unit's namespace exists and hands to the unit under a directory of its
  own. Its shape: a plan field naming the credential beside the file it comes from, a rendering of
  that field in each realiser, and a profile table that stops denying a root-only file to a unit
  which names it as a credential rather than as a path. Designing it here would be designing a
  second delivery mechanism before the first one is safe.
- **Recording the confinement a flakelet entry was realised under (part of C6).**
  `flakelet/read.nix:33-34` hardcodes `trusted` and `operator/read.nix:106` records `profile = null`
  for every entry no statement gave a profile, so the confinement the default realiser applies is
  stated nowhere a reader can see. The two capabilities that own the fields are
  `operator/deployment-build`, which owns what a build records per entry, and
  `realiser/flakelet-artifact`, which owns what the artifact's own metadata carries. Neither is
  written here, and the field is a build fact rather than a delivery fact.
- **Rotation.** Replacing the bytes of a value moves no plan field, and what a rotation has to
  restart is the reload-versus-restart question `deliver-secrets-across-machines` already deferred.
- **Encrypting the operator's value source.** The source is a directory of bytes the operator holds.
  This change checks its posture and refuses a source others can read; where the bytes come from and
  whether they rest encrypted is the store's business and not the command's.

## Capabilities

### New Capabilities

- `operator/machine-identity` (`lib/resolve.nix`, `lib/plan.nix`, and `cli/`): what a deployment
  states about the machine it dials, what the command verifies before it writes a secret there,
  which options a run connects with, and how a test guest's accommodation stays visible.

### Modified Capabilities

- `operator/apply-command`: how the bytes of a value reach a machine, at what mode and owner, from a
  source whose posture is checked; and how a failure on a machine is reported.
- `planner/plan-artifact`: the value-file record states the mode and the owner a delivery writes,
  and a refused secret export carries no bytes beside its row.
- `planner/diagnostics`: a type-mismatch row states the type expected and the type received, and
  never the value.
- `realiser/portable-service-image`: an image carries a mount point for every generated file its
  units name, and a confinement profile is denied per unit rather than per entry.
- `delivery/real-cluster`: the machine layer observes that a delivery in flight leaves the bytes in
  no process table and in no journal.
