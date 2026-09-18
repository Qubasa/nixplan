<!--
A new capability. `operator/apply-command` owns the preflight question a run asks a user-scope
machine before it writes anything there, and the shape of its refusal - that question is
`run-an-entry-without-root`'s, landed
(`openspec/changes/run-an-entry-without-root/specs/operator/apply-command/spec.md:30-53`). This
capability owns the other half: the declaration that makes those facts true, which nothing in this
repository publishes today. It MODIFIES that requirement nowhere - the run still verifies rather
than assumes, and a machine whose declaration was never applied is refused at its first step
exactly as it is now.

What it deliberately does not decide. It decides nothing about which scope a machine is in, which
is a registry fact `planner/machine-platform` owns, and nothing about the order of the steps on a
machine, which `openspec/changes/INTEGRATION.md` writes out once. The bundle for a machine no run
can dial stays named and not designed (`openspec/changes/INTEGRATION.md:81-84`): the declaration
here is a machine's own configuration and not an installer. The sibling changes of this set own
the record, the view and the authoring loop, and this capability consumes none of them.

The conditions. `cli/remote.py:670-729` verifies the facts a user-scope run rests on - the three
fixed roots stated once at `:86-88` and asked at `:683-697`, lingering and the account's manager
(`:698-709`), the account's own portabled and a home traversable by a uid that owns none of it
(`:637-667`, asked where an image entry is placed, `:710`), `systemd-mountfsd.socket` and
`systemd-nsresourced.socket` (`:711-719`), and the kernel's own userns knobs (`:720-728`) - and
creates none of them. The only thing in the tree that creates them is a test machine:
`tests/e2e/guest.nix` declares the account with lingering and `homeMode = "711"` (`:319-328`), the
trusted login (`:335`), the three tmpfiles roots (`:36-49`, `:337-341`), the verity certificate
under `/etc/verity.d` (`:61-68`, `:343-347`), the polkit rule (`:349-362`), the two upstream
sockets by drop-in (`:364-385`) and the user portabled with its D-Bus activation (`:387-392`), each
with an assertion stating why no plan can create it (`:174-193`, `:204-242`). Two of its facts are
not a machine's role: the snakeoil credential a throwaway guest is reached with (`:147-150`,
`:327`) and a systemd rebuilt with `-Dvmlinux-h=provided` because the pinned nixpkgs builds it
where `/sys/kernel/btf` does not exist (`:70-98`, asserted `:196-201`).
-->

## Purpose

Defines the one-time root work a machine needs before a run can write to it as a declaration this
repository publishes rather than as prose an operator follows by hand: which facts the declaration
carries, which facts it refuses to carry because they belong to a particular machine rather than to
the role, which facts it cannot create and therefore asserts, and that the machines this
repository's own tests use are that declaration's consumers rather than a second copy of it.

## ADDED Requirements

### Requirement: The one-time root work of a machine is a published declaration

This repository SHALL publish a declaration a machine's own configuration imports, carrying exactly
the facts a run verifies before it writes to a machine deployed as an account: the deploying
account, its service manager kept alive with nobody logged in, its home traversable by a uid that
owns none of it, that login trusted with the machine's own store, the fixed roots writable by it,
the certificate an image's signature is verified against, the authorization rule that admits the
account's own attach, the daemons an unprivileged mount and user namespace are delegated to, and
the account's own portable-service daemon with the activation it is reached through.

The roots the declaration makes writable SHALL be the ones the command states once, and the
declaration SHALL state no fourth root: a path that moved with the scope would put an account's
name into every entry key that renders one.

The declaration SHALL create these facts at provision time and a run SHALL create none of them: the
run's own question stays a verification, so that a machine whose declaration was never applied is
refused at its first step naming the fact that does not hold.

#### Scenario: A provisioned machine answers every preflight fact

- **WHEN** a machine whose configuration imports the declaration is asked the preflight question of
  a user-scope run placing an image entry
- **THEN** every fact the question verifies SHALL hold
- **AND** the run SHALL take its first step on that machine

#### Scenario: The provisioning declaration states no fourth root

- **WHEN** the declaration is read for the roots it makes writable by the account
- **THEN** they SHALL be exactly the roots the command states
- **AND** the declaration SHALL state no root of its own

#### Scenario: A run creates no provisioning fact

- **WHEN** a run applies entries to a machine deployed as an account
- **THEN** no step of the run SHALL create, enable or relax any fact the declaration carries
- **AND** a machine missing one SHALL be refused at its first step naming that fact

### Requirement: The declaration carries no credential and no key material

The declaration SHALL carry no credential: which logins may reach the deploying account is the
operator's own statement about their own fleet, and a published declaration that shipped one would
admit its own author. It SHALL carry no private key of an image-signing pair either - that half is
an argument of the build and of nothing else - and SHALL take the public half it installs as an
argument of the consumer's own.

#### Scenario: The provisioning declaration carries no credential

- **WHEN** the published declaration is read
- **THEN** it SHALL name no login credential and no private key
- **AND** the certificate it installs SHALL be a value the consumer states

### Requirement: The two facts the declaration cannot create, it asserts

A declaration cannot build its consumer's service manager and cannot choose its consumer's kernel,
so for each of those it SHALL assert the property it needs and name what a reader has to do where
the assertion fails: that the service manager it is configuring exposes the interface an
unprivileged user namespace is delegated through, and that the kernel permits an unprivileged user
namespace at all.

The assertion SHALL fail at evaluation, before a machine is built, rather than leaving an attach to
fail on the machine with a message that names neither the fact nor the declaration.

#### Scenario: A systemd with no user-namespace interface is refused

- **WHEN** the declaration is evaluated against a service manager whose build exposes no
  user-namespace interface
- **THEN** the evaluation SHALL fail naming that property and what to do about it
- **AND** the declaration SHALL NOT rebuild the consumer's service manager itself

#### Scenario: A kernel refusing an unprivileged user namespace is named

- **WHEN** the declaration is evaluated for a machine whose kernel permits no unprivileged user
  namespace
- **THEN** the evaluation SHALL fail naming that knob
- **AND** the message SHALL state that the fact is the machine's and no plan can state it

### Requirement: The machines this repository tests with are the declaration's consumers

The machine image the end-to-end layer boots SHALL import the published declaration for every fact
that declaration carries, rather than restating any of them, so that the path the tests exercise
and the path a reader follows are one text and a fact added to one cannot be forgotten in the
other.

A fact of that image which is not a machine's provisioning SHALL stay the image's own: the
credential a throwaway guest is reached with, and a service manager rebuilt to suit the package set
this repository pins. Each SHALL remain stated where the image states it, with the reason it is not
the declaration's.

#### Scenario: The test machine imports the published declaration

- **WHEN** the image the end-to-end machines boot is read for a fact the declaration carries
- **THEN** that fact SHALL be the declaration's, imported
- **AND** the image SHALL restate none of them

#### Scenario: A guest fact that is not provisioning stays the guest's

- **WHEN** the image is read for its own credential and for the service manager it rebuilds
- **THEN** both SHALL be stated by the image and not by the declaration
- **AND** the image SHALL state why each is a fact of a test machine rather than of a role
