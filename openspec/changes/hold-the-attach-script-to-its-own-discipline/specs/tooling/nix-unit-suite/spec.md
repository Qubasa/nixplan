<!--
A delta against `tooling/nix-unit-suite`, whose current text is
`openspec/specs/tooling/nix-unit-suite/spec.md`. One block, ADDED. That capability's purpose is the
suite contract and "the two properties that are checked by construction rather than case by case";
this is a third of that kind, and it is stated here rather than in a realiser's capability because it
binds every suite that reads a rendered script rather than one realiser's script.

The conditions. A rendered script is reachable from a pure evaluation: `image/default.nix:471`,
`:525` and `:542` render one string each, and `tests/unit/image.nix:47-75` builds that file over a
package set whose `writeShellScript` answers with its own text (`:61`), which is why
`tests/default.nix:4-7` hands that suite the real `nixpkgsLib` - "the one suite that reads a rendered
script". Every check over such a text today picks its subject by hand: one staged path
(`tests/unit/image.nix:2405-2421`), one hand-planted platform string (`:2423-2444`, the fixture at
`:134-139`), one unit list (`:2446-2468`), and in the staging assertions the entry's own directory and
one leaf (`:2470-2495`). Each is satisfied by whatever the renderer does to every other value, which
is how six unescaped interpolations stand in `image/default.nix` (`:426`, `:428`, `:447-450`) with
the suite green and one of their spellings pinned as an expectation (`:1707`).

`A check that cannot fail is not kept` (`openspec/specs/tooling/test-layers/spec.md:264-273`) is the
rule this block serves and is not restated: that capability says a check must be able to fail on the
condition it names, and this one says what makes a scan over a generated script able to, which is
that it cannot choose its own subjects. `Every spec scenario maps to a named test` is untouched.

The evaluating layer is where this lands because the text is a string the evaluation already holds:
a scan there costs one evaluation per entry shape, so the dispositions, the scopes and the values no
grammar reached are all reachable, while a machine observes a rendered script only through what
running it leaves behind.
-->

## ADDED Requirements

### Requirement: A scan over a generated script derives its subjects from the record

A check asserting a property of a generated script SHALL derive the values it looks for in that
script from the record the script was rendered from, and SHALL NOT take them from a list written into
the check. A scan whose subjects are a list holds the renderer to the property for the values
somebody thought of, and a site the renderer gains afterwards is covered by nothing while the scan
stays green.

Such a check SHALL report what it found: how many of its derived subjects the script names, and which
of them fail the property. A subject the script names nowhere SHALL be reported as not found rather
than counted as observed, so that a fixture which stopped reaching the site a check was written for
fails rather than passing over an empty scan.

Where a property of a script is true of one value and false of another only because of what the value
contains, the check SHALL be over a form of the property that does not depend on the value, or the
suite SHALL plant a value the property can be observed on. A scan that cannot distinguish a script
that holds the property from one that does not, for the values its fixture happens to carry, SHALL
NOT be kept as coverage of it.

#### Scenario: A scan over a generated script derives its subjects from the record

- **WHEN** a check asserts a property of every value a generated script names
- **THEN** the subjects it scans for SHALL be the values the record the script was rendered from
  carries
- **AND** a value added to that record SHALL be scanned for without the check being edited

#### Scenario: A scan whose subjects the script never names

- **WHEN** a scan's derived subjects appear nowhere in the script it scans
- **THEN** the check SHALL fail naming the subjects it did not find
- **AND** SHALL NOT report a scan that found nothing as a property that holds
