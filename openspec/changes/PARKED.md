# Parked designs

The `lib/excluded.nix` idiom applied to design work: a construct that was designed, red-teamed and
then deliberately not built is recorded here with the trigger that revives it, so the next reader
finds the analysis instead of re-deriving it - and so nothing here is mistaken for a plan. An
entry leaves this file by becoming a change or by being struck with a sentence saying why.

Three invariants survived the same design round and are live, not parked; `CLAUDE.md` records them
under "Deployment scope" and "Enrollment and the mesh": runtime facts never enter evaluation,
exports bind to names and never addresses, and a secret is sealed to a recipient the registry
declares.

## Decentralized enrollment: membership cards and an offline network key

A machine joins with no coordination server: the operator keeps a network key offline, admission
is a signed card - `pubkey | not_before | not_after | name | signature` - a machine-authored claim
fragment arrives by pull request, CI verifies mechanically, and every peer verifies the card
against the network's public key so no forge setting is a security boundary.

- **Trigger:** the operator requires that no coordination server exist.
- **Recorded hazards, from the red-team:** the renewal paradox (automating card renewal puts the
  signing key online and the offline story collapses into an ordinary CA; the honest fork is
  long-lived cards plus a revocation list, or an online intermediate under the offline root);
  clock skew at admission (a machine with a dead RTC cannot validate a validity window before it
  has the network the validation gates); revocation distribution; ceremony fatigue (re-claims
  should demand a signature by the previous key, reserving the human ceremony for genuine key
  loss).

## The mesh-provider interface

Exchangeable mesh backends behind one typed contract: runtime exports (`fqdn` static, `address`
bounded `any` and tagged per backend, `resolver` machine-local) and three lifecycle verbs the
enrollment pipeline asks of the stated backend - mint a ticket, admit a fragment, retire a node -
the way `operator/read.nix` asks a stated realiser for its rules.

- **Trigger:** a second mesh backend is deployed by a real deployment.
- **Recorded hazard:** an interface extracted from one implementation is shaped by that
  implementation; with one mesh in use the abstraction has nothing to be honest against.

## The name-to-identity phone book, and address-less meshes

For a mesh where the address is derived from a key minted on the machine (iroh's NodeId, a
derived IPv6), nothing can know the address before first boot, so the stable handle is the name
and a signed, gossiped record maps name to current identity and reachability at runtime. Services
read the phone book through a resolver; rendered configuration never carries a peer identity, so
a join rebuilds nothing.

- **Trigger:** an address-less mesh backend lands.
- **Held meanwhile by the live invariants:** exports bind to names, and runtime reachability
  enters no plan - both hold under a centralized mesh today, so the phone book slots in as a
  transport change, not a model change.

## Sealed values on gossip

Deliver a secret to a machine no run can dial by letting the age ciphertext ride the same
replicated channel as the phone book: sealed bytes are harmless in transit, every node stores and
forwards, only the recipient opens.

- **Trigger:** decentralized enrollment lands - the mechanism only pays for itself in a
  no-server world.
- **Recorded hazards:** no forward secrecy (ciphertext resident fleet-wide meets a future key
  compromise; a TTL or tombstone bounds the window), and no crisp revocation cut-off - a
  transactional store is the upgrade when revocation timing starts to matter.

## Slot pools and ticket policies

A multi-state slot lifecycle - declared, ticketed, claimed, retired - with per-slot admission
policy and pools of interchangeable slots claimed by whoever boots next from a shared installer.

- **Trigger:** more than about ten friend machines, or a genuinely shared installer.
- **Note:** `enroll-a-friend-machine` covers the single-machine case with one registry row and
  one single-use credential; a pool is that row and credential multiplied, and earns machinery
  only when the multiplication hurts.
