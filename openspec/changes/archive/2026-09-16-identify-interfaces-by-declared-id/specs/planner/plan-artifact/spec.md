## ADDED Requirements

### Requirement: A published capability records the identity its interface claimed

An entry's record of a capability it provides SHALL carry the identity its interface claimed, beside
the interface's name and declaring file that the record already carries. The field SHALL be absent
where the interface claimed no identity, never null and never the interface's name, so that a reader
cannot mistake an unclaimed interface for one claiming its own label.

A claim SHALL NOT change an entry's key. Two deployments that differ only in whether an interface
claims an identity SHALL produce the same entry keys, because a claim decides which edges exist and
not what any entry was rendered from.

#### Scenario: A claimed interface records its claim

- **WHEN** an entry provides a capability whose interface declares an identity
- **THEN** the plan's record of that capability SHALL carry that identity
- **AND** SHALL still carry the interface's name and its declaring file

#### Scenario: An unclaimed interface records no claim

- **WHEN** an entry provides a capability whose interface declares no identity
- **THEN** the plan's record of that capability SHALL carry no identity field at all
- **AND** the record SHALL otherwise be byte-identical to the one produced before claims existed

#### Scenario: A claim does not re-key an entry

- **WHEN** an interface adopts an identity and nothing else about a deployment changes
- **THEN** every entry key in the plan SHALL be the one it was before
