<!--
A delta against `planner/interface-fold`, whose base text lives in the unarchived changes
`hold-declaration-shape-and-fold-set-reads`, `normalise-folds-and-report-refused-reads` and
`identify-interfaces-by-declared-id`. `openspec/specs/` is empty in this repository, so the base
text is read from those changes.

The requirement below is ADDED. It reads against `A malformed or raising fold refuses the read, not
the evaluation` (last restated by `normalise-folds-and-report-refused-reads`) and against `A
refusal cannot break the table it travels to` (`hold-every-stated-guarantee`,
`planner/diagnostics`), both of which stand: a refusal still leaves the slot absent rather than
present and empty, a refusal that is not a sentence is still a row rather than a coercion, and the
rest of the plan is still produced. What is added is the channel the refusal travels through.
`lib/resolve.nix:1939-1942` reads a returned record carrying a `refused` attribute as a refusal, so
the sentinel is in band: `tests/unit/counterexamples.nix:790` declares the fold a partitioning
policy is written as, whose successful result names its own refused members, and watches the
planner read that success as a refusal of the whole set and call a correct deployment
inapplicable.
-->

## ADDED Requirements

### Requirement: A fold's refusal is a marker its own result cannot imitate

A fold's refusal SHALL be distinguishable from every value that fold can successfully return. The
channel a refusal travels through SHALL be a marker the planner hands the fold's author, built the
way a named fold itself is built, and a fold's own successfully computed result SHALL NOT be able to
imitate it however that result is shaped and whatever its attributes are named.

A fold SHALL therefore be free to return a record carrying an attribute of any name, including the
name the refusal channel is spelled with today, and such a result SHALL be delivered to every
consumer of that read as an accepted value. A deployment whose fold accepts every value it was given
SHALL be applicable, and the planner SHALL emit no refusal row for it.

A refusal SHALL still carry the sentence an operator reads, and the division of the row SHALL be
unchanged: the fold supplies the message, the planner supplies the identifier, the consuming entry is
the subject, and the severity is the planner's, which a module SHALL NOT be able to state. A refusal
carrying no sentence, or carrying something other than a sentence, SHALL remain a row of its own
naming the interface and the slot rather than a coerced message or a row with nothing in it.

A refused read SHALL leave the slot absent from the values the consuming implementation receives,
never present and empty, exactly as a raising fold does, and the rest of the plan SHALL still be
produced with the table reporting the plan as not applicable.

#### Scenario: A fold may return an attribute called refused

- **WHEN** a fold partitions the set it is given and its successful result carries an attribute named
  the way the refusal channel is spelled
- **THEN** the planner SHALL deliver that result to the consuming implementation as the slot's value
- **AND** no refusal row SHALL be emitted for that read
- **AND** the plan SHALL be applicable

#### Scenario: A fold refuses the set it was given

- **WHEN** a fold refuses the set it is given, through the marker the planner provides, with a
  sentence naming what it refused
- **THEN** the planner SHALL emit an error row whose message is that sentence, whose subject is the
  consuming entry and whose identifier and severity are the planner's
- **AND** the slot SHALL be absent from the values that consumer's implementation receives
- **AND** the table SHALL report the plan as not applicable
- **AND** every entry the refusal did not touch SHALL still be planned
