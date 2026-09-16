<!--
A delta against `realiser/secrets-configuration`, whose base text lives in the unarchived changes
`generate-values-with-nixos-secrets` and `report-a-secrets-refusal-as-a-row`, the second of which
restated three of the first's requirements whole. `openspec/specs/` is empty in this repository, so
the base text is read from those two.

The requirement below is ADDED. "The deploy script is rendered from the plan" is not restated: what
it says about the machines a step addresses, the path it writes and the bytes it does not carry is
unchanged and still that change's. Its sentence "the rendered step SHALL contain none of the bytes
of any value" is about the script's own text, and it holds - the defect is about a file the step
makes while it runs, which no requirement covers today.

The condition: `secrets/backend.nix:91-96`. `deliver` makes a temporary with `mktemp`, has the store
backend's own `get` write the decrypted bytes into it at `:93`, pipes it over ssh at `:95`, and never
removes it; `header` (`:82-103`) installs no trap. `set -eu` at `:86` is why a trailing removal is
not the fix: a refused ssh exits the function and the script, so a line after it is not reached.

Layers. "The rendered step removes the plaintext it fetched" is read off the rendered text in
`tests/unit/secrets.nix`, which already renders the step and asserts its lines
(`tests/unit/secrets.nix:137-141,453-476`); a nix-unit suite is a pure evaluation and cannot run a
shell, so that scenario is honestly a reading and not a run. The two scenarios that run the step
belong to `tests/e2e/generated-secret/`, which is the only place the step exists as a built store
object beside a backend that answers (`tests/e2e/generated-secret/test_generated_secret.py:330-337`
is the invocation, and `tests/e2e/generation.py:462-474` builds its argv); neither of them needs a
machine to answer, and the folder skips itself where the external tool cannot be resolved.
-->

## ADDED Requirements

### Requirement: The rendered step leaves no plaintext on the host that ran it

The rendered delivery step fetches each file's decrypted bytes onto the host that runs it, because
the external contract hands its backend a path to write rather than a stream. That file SHALL be
removed before the step ends, on every path out of it: a delivery that completed, a delivery a
machine refused, a fetch that failed, and an interrupt.

The removal SHALL be installed before the first fetch and SHALL NOT be a command after the send. The
step runs under `set -eu`, so a refused send exits the step and a command written after it is never
reached; a removal that only runs on the successful path is what leaves the bytes behind exactly
when something went wrong.

At no point SHALL the plaintext of more than one file exist on that host, so a step delivering a
hundred files leaves neither a hundred files behind nor a hundred beside each other while it runs.
What does exist SHALL be readable by nothing the account running the step is not.

A signal no process can trap SHALL be the one case this cannot cover, and what survives it SHALL be
one file rather than one per delivery.

#### Scenario: The rendered step removes the plaintext it fetched

- **WHEN** the step rendered from a plan carrying delivered values is read for what it does with the
  file it fetches into
- **THEN** the removal SHALL be installed before the first fetch and SHALL cover a normal exit, the
  exit a refused send causes, and an interrupt
- **AND** the plaintext of at most one file SHALL be able to exist at a time

#### Scenario: A delivery the machine refuses leaves no plaintext

- **WHEN** the rendered step is run against a send that refuses, with the fetch answering bytes
- **THEN** the step SHALL exit non-zero
- **AND** no file holding any byte of any value SHALL remain in the directory its temporaries were
  made in

#### Scenario: A completed delivery leaves no plaintext

- **WHEN** the rendered step delivers every pair of a file list it was given and exits zero
- **THEN** no file holding any byte of any delivered value SHALL remain in the directory its
  temporaries were made in
- **AND** the bytes on each recipient machine SHALL be the bytes the backend answered
