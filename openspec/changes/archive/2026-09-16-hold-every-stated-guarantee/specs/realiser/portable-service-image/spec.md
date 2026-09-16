<!--
A delta against `realiser/portable-service-image`, which lives in the unarchived
`emit-systemd-portable-service-images` change and was last restated by
`generate-values-with-nixos-secrets` and `report-every-refusal-as-a-row`. The condition is
`image/default.nix:144-172`: the attach script's preamble sets `set -eu` and no umask, `assemble`
creates the staged file with `: > "$root"<staged>`, appends each fragment with `cat`, and applies the
declared mode only afterwards. A configuration file rendering a secret reference therefore exists at
the login umask while the secret is written into it, and keeps that mode if the script exits between
the append and the mode. This is not covered by `deliver-a-secret-without-exposing-it`, whose subject
is the command's argv, the per-generator mode and owner, and host verification.
-->

## Purpose

Defines the image a machine attaches as one that carries no bytes of its own, whose units are confined
by a stated profile, and whose staging of a file on the host never widens who can read it.

## ADDED Requirements

### Requirement: A staged file carries its declared mode before it carries bytes

A file the realiser assembles on the host SHALL have its declared mode before any byte is written
into it, so that no window exists in which the assembled file is readable by anyone the declaration
did not admit. The mode SHALL NOT depend on the environment the attach runs in.

A failure part way through assembling a file SHALL NOT leave that file readable more widely than its
declaration states. A file whose assembly did not complete SHALL either carry its declared mode or
not exist.

#### Scenario: A staged file renders a secret

- **WHEN** a configuration file declares a mode and renders a reference to a generated secret
- **THEN** the file on the host SHALL carry that mode from the moment it exists
- **AND** at no point SHALL it be readable by a user the mode excludes

#### Scenario: The assembly of a file fails part way

- **WHEN** the assembly of a declared file stops after some bytes are written
- **THEN** what remains on the host SHALL NOT be readable more widely than the declared mode
- **AND** the next attach SHALL be able to assemble the file again

#### Scenario: The mode does not depend on the attaching environment

- **WHEN** the attach runs with a permissive file-creation mask
- **THEN** the staged file's mode SHALL be the declared one
- **AND** SHALL NOT be widened by the environment
