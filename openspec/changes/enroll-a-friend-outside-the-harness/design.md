## Context

See `proposal.md` - Why. What shapes the approach is where the landed proof put each fact, and one
mechanical obstacle that turns out to explain every part of the gap.

`enroll-a-friend-machine` decided the model and this change must not redecide it. Membership is
centralized on a coordination server the operator runs, the sync is one-way from registry to
server and the server's database is never a source the planner reads, the credential is a
generated secret whose bytes stay out of every plan field and every argument vector, admission is
verified after the fact rather than automated, and the mesh name is the address
(`openspec/changes/enroll-a-friend-machine/design.md:41-78`; the requirements at
`specs/operator/machine-enrollment/spec.md:11-92`). This change publishes the surface those
decisions already imply and adds no rule of its own about membership.

The obstacle. The coordination server's own tool decides a configuration's format from the file
extension, so it refuses the store object the unit is bound - named by a digest with no suffix -
and it cannot read the path the entry declares either, because that path exists inside that unit's
mount namespace alone. The folder works around both with one `install` of a copy under a host path
of its own (`tests/e2e/friend-enrollment/test_friend_enrollment.py:192-203`, run at `:393`). That
one obstacle is why the declared generator has never run: its program would need the same
configuration (`deployment/mint.sh:25-32`), and a generator's program is run by the external
secret backend with `out` set (`secrets/read.nix:518-543`,
`tests/e2e/generation.py:562-572`) on the generation host, which is not the machine the server's
socket is on (`hub.nix:144`). Remove the obstacle and both halves close at once.

The tree already has every other mechanism this change needs. A fact stated beside the deployment
rather than inferred is `realise`, read by plan key and refused where it names no entry
(`operator/read.nix:637-650`, `:690-703`), and a fact published per realiser rather than restated
is the `scopes`/`holdings` table (`:753-763`). A published output that is not a path inside this
source is `flake.operator` (`flake-module.nix:65-70`), and a module handed to a consumer as an
argument rather than as a path is how every folder receives `operator`
(`flake-module.nix:155-173`) and how the guest receives the flakelet module (`:189-194`) - which
is also the only way a folder can consume anything, since `tests/unit/layers.nix:210-222` refuses
a path leaving the folder and `:224-235` refuses naming a sibling. A one-time root fact a run
verifies and never creates is the preflight (`cli/remote.py:670-729`).

## Goals / Non-Goals

**Goals:**

- An operator mints a credential, reads what the server admits and ends a membership by running
  the command, with no shell composed by hand and no knowledge of the server's own flags.
- A deployment places a coordination server by composing a published module, and every choice the
  cluster made is visible as a declaration rather than buried in a module's text.
- The one-time root work of a machine is a declaration a machine's own configuration imports, and
  the machine the tests use is that declaration's consumer rather than a second copy of it.
- Every line the landed change drew stays drawn: no runtime fact enters evaluation, the credential
  is a generated secret handed over out of band, and its bytes enter no argument vector.
- The limit is stated rather than dressed up: which machines can receive a user-scope entry today
  is a property of six provisioning facts, and the proposal says so before it promises anything.

**Non-Goals:**

- The self-installing bundle for a machine no run can dial. `openspec/changes/INTEGRATION.md:81-84`
  names it and states what keeps it reachable; this change adds nothing it would have to undo - a
  verb is a step against a machine a run can already dial.
- A mesh-provider abstraction. Parked with its trigger - a second mesh backend deployed by a real
  deployment - and its recorded hazard, that an interface extracted from one implementation is
  shaped by that implementation (`openspec/changes/PARKED.md:29-38`). The published module is one
  backend's module, named as such.
- Slot pools and ticket policies. Parked with the trigger of about ten friend machines or a
  genuinely shared installer (`openspec/changes/PARKED.md:65-73`).
- A machine whose systemd is older than the per-user portabled. The floor is systemd 260 and the
  pinned nixpkgs resolves 261.1 (`openspec/changes/run-an-entry-without-root/design.md:22-23`);
  below it there is no user portabled to address and the provisioning module has nothing to
  declare.
- Provisioning a machine whose configuration this repository cannot express. `cli/remote.py:670-729`
  stays the checklist for that machine, and a published module for a second configuration system
  is not designed here.
- Automating admission. The operator's check after a join stays the server's own node list, which
  is what the `members` verb prints and nothing more.

## Decisions

### D1 - The deployment states which entry coordinates the mesh, and nothing infers it

The deployment build takes one more statement beside `realise`, naming the plan key of the entry
that runs the coordination server. A statement naming no placed entry is one error row, exactly as
a `realise` key naming no entry already is (`operator/read.nix:690-703`), and the deployment record
publishes the coordination facts the way it publishes each realiser's own statements
(`:753-763`), so a verb reads them off the built deployment and derives nothing.

Rejected: **recognising the coordination entry by its module, its unit's command text or its plan
key.** The reading classifies a plan record by what it records and never by the text of its key,
and it asks a stated realiser for its rules rather than testing which realiser it is
(`operator/read.nix:156-160`, and the record-classification rule under "Realisers" in
`CLAUDE.md`). A verb that recognised a server by a package name in a closure would be the first
name-matching reading in the tree and would drift the moment a second module published one.

Rejected: **a flag on the verb naming the entry.** An operator would restate on every invocation a
fact the deployment already holds, and two invocations naming two different entries of one
deployment would both be accepted. The statement is a fact about the deployment, so it lives
beside the deployment.

### D2 - The operator's configuration is a store object the module renders

The published module renders one object whose name carries the extension the server's loader
requires and whose content states only what an administrative invocation needs: the socket the
serving unit was declared with. It is in the entry's own closure, so the copy the apply already
makes puts it on the machine, and the administrative program the module publishes names it. The
unit is unchanged: it keeps reading the declared `configData` file whose bytes the plan holds and
whose record is the store's own (`hub.nix:152-163`), which is what lets a realiser bind it.

Both objects are built from one derivation of one socket path inside the module, so there is no
second copy to disagree. What this deletes is the workaround: the test's
`install -D -m 0444 <store object> /run/.../config.yaml` (`test_friend_enrollment.py:203`,
performed at `:393`) and the host path it invents.

Rejected: **declaring the configuration in a record the realiser installs rather than binds, so
its bytes land under the entry's staging directory.** That works - an installed file's bytes are
at `stagedPath`, which preserves the declared path and therefore its extension
(`image/read.nix:426-428`, the choice at `:555-559`) - and it is wrong twice. It makes the
operator-facing path a fact only the stated realiser knows, so the command would have to learn a
per-realiser path rule, and a rule read in nix and again in python is one rule with two readings,
which is the hazard `CLAUDE.md` records for a machine's own holdings. And it re-keys the entry's
image on every edit to the configuration for a reason that has nothing to do with the unit.

Rejected: **an API key and the server's HTTP API.** It replaces a socket the machine already
protects by file permission with a second bearer credential the tree would have to mint, store and
rotate, to reach the same three verbs.

### D3 - `invite` runs the declared generator where the server answers

The credential stays exactly what `enroll-a-friend-machine` requires: a generated value of the
deployment, minted by the generator declared on the coordination entry, secret, delivered to no
machine, read out of the value source and handed over outside the tree
(`openspec/changes/enroll-a-friend-machine/specs/operator/machine-enrollment/spec.md:34-41`).
`invite` is the one thing missing: it runs that value's own `program` - the store path the plan
records - on the coordination entry's machine, with `out` set to a directory of the run's own,
which is the contract the external backend already runs a generator under
(`secrets/read.nix:518-543`, `tests/e2e/generation.py:562-572`). The files the program wrote come
back on the step's output stream and are written into the value source at the paths the plan names
for that value's files.

Two consequences are the point. The program no longer reads anything from an environment nobody
sets (`mint.sh:25-32`): the module renders it naming the administrative object of D2, and the
numeric owner id the server's own flag demands is read back inside the program the way the folder
reads it today (`test_friend_enrollment.py:456-462`, asserted at `:485-503`). And the bytes never
reach an argument vector: they travel on a step's stream, which is the discipline the sealed copy
already follows, and `tests/e2e/test_harness.py:3602-3645` asserts every encoding of them is
absent from every recorded vector.

Rejected: **the verb minting with its own invocation of the server's tool.** The credential would
then be the command's bytes rather than the declared generator's, and the deployment's
`vars.enrollment` declaration - the `expiry` it states, the file name, the secrecy - would be
decoration beside a second minting the command owns. One minting site, declared in the deployment.

Rejected: **printing the credential on the verb's output for the operator to copy.** The landed
change states the operator reads it out of the value source, which is where every other generated
secret is, and a verb that prints bytes puts them in a terminal's scrollback and in whatever
captures a run's output. The verb prints the path and the expiry it minted under, and no byte of
the key.

Rejected: **teaching the external secret backend to run this program on a remote machine.** The
backend's contract is a local program and a local store, and a generator that needs a machine is
not a property of that backend but of this value.

### D4 - A verb is a step of the command, and prints lines rather than a record

Each verb runs one step on the coordination entry's machine over the channel every remote step
uses, addressed by the machine's own scope - `--user` and an explicit `XDG_RUNTIME_DIR` where the
scope is `user`, for the reason every user-bus step states it (`CLAUDE.md`, "The operator's
command"). A failure is the command's own refusal naming the entry, the machine and what the
machine printed, never a traceback and never the argv, which is the shape every machine refusal
already has.

The verbs define no machine question of their own. `answer-a-machine-question-as-a-record` owns the
structured record a machine question answers with, and `openspec/changes/INTEGRATION.md` records
that ownership; an enrollment verb asks the coordination server and never asks a machine what it
holds, so it extends that record with nothing and reads none of it. A listing may be printed
verbatim: the server masks a credential in its own listings to the first twelve characters, which
is the fact the folder records beside the question it asks (`test_friend_enrollment.py:237-245`).

`expel` takes the identifier the listing printed, and not a machine of the registry. A node is the
server's own fact, runtime facts enter no evaluation, and the registry's name for a machine is not
the server's name for a node - so the two verbs compose, `members` first and `expel` on what it
printed, rather than the command inventing a mapping between two namespaces.

### D5 - The published module refuses to default what a cluster chose, by taking it as an argument

The module is a function, and a fact it refuses to default is an argument of that function - the
shape the folder's module already has (`hub.nix:9`). A composing root that omits one fails the
evaluation of its own deployment file, before `mkPlan`, which is a refusal a default can never be.
Two facts are arguments: the url a client is configured with, because the cluster's plain HTTP over
the machine's address (`hub.nix:68`) is a choice no published module may make silently, and the
admission policy, because the cluster's empty policy path (`:127-132`) admits everything.

Everything else the cluster chose becomes a settings knob whose default is the value a published
module can defend, and the folder states its own: the listener (`hub.nix:72`), the relay's client
verification and its empty url and path lists (`:97-104`), the embedded relay region (`:88-96`),
the metrics listener (`:75`), the prefixes (`:80-83`), the node expiry (`:108-112`) and the DNS
statements (`:133-143`). The folder's four cluster-only choices then read as four declarations in
its own deployment, which is the honest place for them.

Rejected: **a settings knob with no default, read inside `impl`.** An absent attribute read there
raises, the guard catches it and the deployment earns `module-raised` plus `impl-missing` - a
refusal that names the module and not the fact the operator failed to state.

Rejected: **defaulting to the cluster's own values.** A published module defaulting
`verify_clients` off, or an empty ACL policy, ships the cluster's compromises to every consumer,
and the reason each was chosen (`hub.nix:97-101`) is a property of a network with no route to
anybody else's.

### D6 - The provisioning module carries what the preflight verifies

The module declares exactly the facts `cli/remote.py:670-729` asks about: the account with
lingering and a home traversable by a uid that owns none of it, that login trusted with the
machine's store, the three fixed roots writable by it, the verity certificate whose private half
signs the images this operator builds, the polkit rule admitting the account's portable and
mount actions, `systemd-mountfsd` and `systemd-nsresourced` enabled, and the user portabled with
its D-Bus activation. The roots are the ones stated once in `cli/remote.py:86-88`, and the module
states no fourth.

It carries no credential and no key material: which logins may reach the account is the operator's
own statement, and the verity private half is an argument of the image build and of nothing else.
And it does not rebuild the consumer's systemd: it asserts that the systemd it is configuring
exposes the user-namespace interface, naming the reason a nixpkgs whose sandbox has no
`/sys/kernel/btf` does not (`tests/e2e/guest.nix:70-82`, the guest's own assertion at `:196-201`),
and it asserts the kernel it is configured on permits an unprivileged user namespace.

The line therefore falls exactly twice. `tests/e2e/guest.nix` keeps the snakeoil credential
(`:147-150`, `:327`) and the rebuilt systemd (`:70-98`, `:368`); everything else it declares for
the account moves into the module and the guest imports it - the account (`:319-328`), the trusted
login (`:335`), the tmpfiles roots (`:36-49`, `:337-341`), the certificate install (`:61-68`,
`:343-347`), the polkit rule (`:349-362`), the two sockets (`:364-385`) and the user portabled
(`:387-392`). The guest keeps the verity *pairs* of its folders, because one pair per folder is a
test's fact (`:51-59`), and hands the module their public halves.

Rejected: **publishing the rebuilt systemd as part of the module.** It is a property of one
package set's build sandbox rather than of a machine's role, a consumer whose systemd already
carries the header needs none of it, and it would put a systemd rebuild in the closure of every
machine that imports the module.

Rejected: **leaving provisioning documented rather than published.** The facts are verified per
run by the preflight and created by nothing, so a wiki page is the only thing between a declared
machine and a run that refuses at its first step. A declaration is also what makes the demo honest:
a friend running NixOS imports one module, and that is the whole of the second half of the
enrollment ceremony.

### D7 - The folder proves the verbs, and stops holding what a product owns

`tests/e2e/friend-enrollment/` keeps every phase the landed change wrote and changes what performs
it: its hub is a consumer of the published leaf module handed to it as an argument the way
`operator` is (`flake-module.nix:155-173`), and each membership act is a verb of the command. Its
own shell keeps only what a test needs: the throwaway presenter that spends a spent key
(`test_friend_enrollment.py:248-263`), the operator's userspace membership
(`tests/e2e/delivery.py:614-696`) and the reading its assertions make. The `headscale` package in
the guest's system profile (`tests/e2e/guest.nix:245-246`) goes with the hand-composed
invocations: the tool arrives in the entry's own closure, which the assertion beside it already
states is one store path and not two.

The folder's own `mesh.nix` stays: a domain, a port, an expiry and a name function read by both
halves (`mesh.nix:9-31`) are the cluster's declarations, and they become the arguments and
settings the published module takes.

### D8 - This change lands after two of its set and consumes rather than defines

`bind-a-value-an-entry-did-not-generate` owns the binding of a host path for a value an entry did
not generate and lands first; `answer-a-machine-question-as-a-record` owns the structured record
and the two restored diagnostics fields and lands second; `show-a-deployment-in-a-browser` and
`author-a-deployment-from-outside` own the view and the authoring loop. This change is one of the
three that may land in any order after those two (`openspec/changes/INTEGRATION.md:113-122`), it
defines no machine question and no record of its own, and that file is the one place the set's
order and its shared seams are written out: the two tooling requirements deltaed more than once
(`:138-147`), the one other delta of `delivery/real-cluster` (`:149-150`), the guest image this
change alone may edit (`:152-156`), the perf gate and this change's task 1.1 (`:158-163`), and the
excuse discipline every change of the set keeps (`:165-168`). The deployment record's version is
read off `cli/manifest.py` rather than assumed, the way `INTEGRATION.md:33-39` records for the
production set.

## Risks / Trade-offs

- **A generator program now has two runners: the external backend and this verb.** → The contract
  is the same one in both - one store path, run with `out` set, files written under it
  (`secrets/read.nix:518-543`) - and the verb asserts the file set the plan names for the value,
  refusing a program that wrote something else. What differs is the host it runs on, which is the
  fact the value is about.
- **A verb runs a program out of the entry's closure on the machine, so a run against a machine
  whose copy is stale runs a stale program.** → The verb refuses where the machine does not hold
  the path this build names, with the same sentence an apply's missing copy earns, and the fix is
  an apply.
- **The published mesh module is one backend's module and will look like an abstraction.** → It is
  named for the backend it configures, the mesh-provider interface stays parked with its trigger
  (`openspec/changes/PARKED.md:29-38`), and nothing in `lib/` gains a mesh concept.
- **The provisioning module cannot make an arbitrary machine eligible.** → Stated in the proposal
  as the demo's honest limit rather than mitigated: six facts, five declarable and one a rebuild on
  the pinned nixpkgs, and a machine nobody can configure stays a member that receives no entry.
- **Editing the guest image re-keys every folder's snapshot cut.** → One edit, `rookery snapshot
  gc --all` after it, the cost paid once - the same trade the landed change made for the mesh
  packages.
- **Three more subcommands widen the command's surface.** → Each is one step and one refusal, the
  parser table is the one place a subcommand is registered (`cli/planner.py:145-151`), and the help
  of each states every constraint it enforces, which is what `tooling/repository-shape` already
  requires of the five.

## Migration Plan

Nothing in an existing deployment moves. A deployment that states no coordination entry is read
exactly as it is today, so every fixture, golden and plan is byte-identical, and the enrollment
verbs refuse on a deployment that states none, naming the statement to add. The published modules
are new files: no existing deployment composes the leaf module and no existing machine imports the
machine module until someone writes the line.

The two rewrites are staged so that neither is a flag day. The folder's hub becomes a consumer of
the published module in one edit whose evidence is the folder's own plan comparing equal but for
the entry key the module's own text changes, and the guest imports the provisioning module in one
edit followed by `rookery snapshot gc --all`. `tests/e2e/guest.nix` and the published module are
one text from that edit onward, which is what makes a later provisioning fact impossible to add to
one and forget in the other.
