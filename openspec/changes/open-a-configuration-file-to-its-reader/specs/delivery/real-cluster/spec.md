<!--
A delta against `delivery/real-cluster`, whose base text lives in the unarchived changes
`prove-plan-on-real-machines`, `apply-deployments-with-an-operator-command`,
`deliver-secrets-across-machines`, `deliver-a-secret-without-exposing-it`,
`generate-values-with-nixos-secrets`, `strip-planner-tests-to-unit-and-e2e`,
`resume-e2e-machines-from-snapshots`, `make-an-apply-observable`,
`run-a-shared-database-on-real-machines` and `give-every-instance-its-own-database`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Both requirements below are ADDED and both are about the folder
`run-a-shared-database-on-real-machines` created. `A stateful entry survives the restart of its own
service` and `Two instances take one capability each from one provider instance` are unchanged:
what this delta adds is that the setup those tests exercise is a declaration rather than a script,
and that a second apply converges what the deployment names.

Where the ownership of a configuration file is proven is stated here rather than assumed. This
folder's entries are realised by the store-backed realiser, which installs nothing on a machine, so
every configuration file it declares states the record a store object carries. What PostgreSQL
checks the ownership of is its data directory, which the service manager creates owned by the
account the unit declares; the authentication file is read by that same account and holds no
credential. A configuration file that states an account of its own is therefore proven under the
image realiser and in the unit suites, and this folder proves the three declarations a store-backed
deployment can make.

The conditions, all in `tests/e2e/shared-postgres/deployment/`: `init.sh:14` creates the data
directory by hand because no declaration can state its mode; `init.sh:16` guards the bootstrap with
a shell test; `init.sh:25-31` writes the authentication file with a heredoc and installs it inside
the data directory because `configData` cannot name an account; `init.sh:35-39` starts a private
postmaster against `initdb`'s own configuration, so `--auth-host` at `init.sh:20` and not the
declared `password_encryption` decides how a role's password is hashed; `init.sh:87-92` only ever
creates a database, so a changed owner at `instances.nix:13` never reaches one that exists; and
`init.sh:79-90` and `consume.sh:49` interpolate an owner, a database and a label into SQL without
the escaping `init.sh:74` applies to the password.
-->

## ADDED Requirements

### Requirement: A stateful service's setup is declared rather than scripted

The folder's cluster SHALL obtain its data directory, its authentication file and its one-time
bootstrap from declarations the plan carries, and its setup step SHALL create none of the three. The
data directory SHALL be a directory the service manager creates for the unit, at the mode the server
requires and owned by the account the unit declares, so that the step neither makes a directory nor
chooses its mode. The authentication file SHALL be a configuration file of the deployment, at a path
the module derives from its own entry's identity rather than one the deployment states, and the
server SHALL be told where it is by the configuration file the module already declares. The
bootstrap SHALL be a unit of its own whose start is conditional on the absence of the file that
proves the cluster exists, and the step that applies roles and databases SHALL run on every apply.

One declared file SHALL decide how a role's password is hashed: the private server the setup step
starts to apply roles SHALL read the same configuration file the published server reads, so no flag
of the initialisation states a second answer.

#### Scenario: The init step creates no directory of its own

- **WHEN** the folder's deployment is applied to a machine that has never run it
- **THEN** the data directory SHALL exist before the step runs, created by the service manager from
  the declaration
- **AND** the step's own script SHALL contain no directory creation

#### Scenario: The data directory arrives at the mode the server requires

- **WHEN** the cluster's units are active on a machine
- **THEN** the data directory SHALL be at the mode the declaration states and owned by the account
  the unit declares
- **AND** the server SHALL have started against it without refusing its permissions

#### Scenario: The authentication file arrives as a declared file

- **WHEN** the same machine is asked what it holds at the path the module derived
- **THEN** the authentication file SHALL be there with the bytes the plan holds
- **AND** the running server SHALL name that path as the file it read
- **AND** the path SHALL appear in the plan rather than in any declaration of the deployment

#### Scenario: The bootstrap runs once and is skipped after

- **WHEN** the deployment is applied twice to one machine
- **THEN** the bootstrap unit SHALL report having done its work on the first apply and having been
  skipped on the second
- **AND** the step that applies roles and databases SHALL have run both times

#### Scenario: One file decides how a password is hashed

- **WHEN** a role's password is applied by the setup step and the role then authenticates over the
  network
- **THEN** the hashing method SHALL be the one the declared configuration file states
- **AND** no flag of the initialisation SHALL state a method of its own

### Requirement: A second apply converges the roles and databases the deployment names

Applying the folder's deployment SHALL leave the cluster holding what the deployment names, and not
merely what it named the first time it was applied. A database that exists and whose declared owner
has changed SHALL be owned by the declared owner after the apply, and a role that owned it and is
no longer named SHALL no longer be able to log in. A role SHALL NOT be dropped: what the deployment
states is who may log in, not which of a machine's objects to delete.

Every value the step interpolates into SQL SHALL be escaped at the site it is interpolated, as an
identifier or as a literal according to which it is, so that a name carrying a quote is one name and
never a statement.

#### Scenario: A changed database owner takes effect on a second apply

- **WHEN** a deployment whose declared owner of an existing database differs from the one applied
  before is applied to that machine
- **THEN** the database SHALL be owned by the newly declared role
- **AND** the data written under the previous owner SHALL still be readable through it

#### Scenario: A role the deployment no longer names cannot log in

- **WHEN** the same apply has finished
- **THEN** the role the deployment no longer names SHALL be refused a login with its own credential
- **AND** the role SHALL still exist, so nothing it owned was deleted with it

#### Scenario: An identifier carrying a quote is not SQL

- **WHEN** a consumer whose declared label carries a quote writes its record
- **THEN** the record SHALL hold that label verbatim
- **AND** the step SHALL report no SQL error, so the quote was escaped rather than parsed
