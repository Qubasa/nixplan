# Export atoms, and this file is where the folder disagrees with its siblings.
#
# Every other folder writes a quadruple. §32.1 adopted `type`, `locality`,
# `lifecycle` and `secrecy`, made the first two mandatory, and made an omitted
# `secrecy` mean `public`. The four atoms below write TWO fields. That is a
# proposal to narrow §32.1 and not a folder that forgot two keys, and it is
# marked here rather than in a README so that a reader who opens only this file
# still sees it.
#
#   atom              type              secrecy
#   publicKeyText     string            public
#   localPrivateKey   secretRef         secret
#   repoUrl           url               public
#   quotaGiB          int               public
#
# The rule the omissions follow: A BOUND EARNS ITS PLACE WHEN THE TARGET ALREADY
# HOLDS THE DISTINCTION THE PLANNER WOULD CHECK AGAINST. Three fields, three
# answers, and the target is clan-core as it is rather than as the design wants
# it.
#
# `secrecy` stays. clan-core already gives every generated file a `secret` flag
# (`modules/clan/vars/settings-opts.nix:53`) and a `deploy` flag
# (`nixosModules/clanCore/vars/interface.nix:81`), so the tag exists on the
# producing side today and checking a slot against it is a join
# over data that is already there. It is deliberately the same word on a `vars`
# file below in ../modules/borg-push/client.nix and on an export here, for the
# reason §29.3 gives for reusing `fixed`: one concept gets one spelling, and a
# second spelling would have implied a second rule.
#
# `locality` goes. It caps where a value may be read from, and clan-core's six
# registered export interfaces (`modules/clan/top-level-interface.nix:421-427`)
# have nothing machine-local in them: `peer` carries a name, a port, a user and
# hosts, `networking` carries a priority and a module name. A field that would
# admit exactly one value on every atom in the target is a field that refuses
# nothing, and the corpus has already paid for one of those:
# its instance-as-group sketch records the atom it used to
# hold as `korora.ref` applied to nothing, "a reference to anything, which
# refuses nothing", and §32.7 deleted it.
#
# `lifecycle` goes. Everything clan-core evaluates is build-time static.
# `probed` presupposes a fact register and `dynamic` presupposes the §14 watch
# contract, and neither exists in the target, so every atom would be written
# `static` and the bound would be a constant.
#
# What the two omissions delete is larger than two fields, which is the point.
# With one declaration site instead of two — the interface states a fact and no
# provider restates a tag — §32.2's three lattices have nothing to be lattices
# over, §32.2's containment relation has nothing to relate, §32.4's
# readability-follows-the-tag rule has no tag to follow, and §32.5's two
# dispositions of a cross-machine `machine-local` read have no `machine-local`
# to dispose of. Four of §32's seven rules lose their subject rather than being
# argued with.
#
# Each field has a trigger that brings it back, and neither trigger is a
# preference:
#
#   `locality`  — the first export in the target whose value is a unix socket
#                 path or a loopback port. Then `machine-local` is a fact about
#                 an object rather than a policy, ../plan/diagnostics.txt gains
#                 the row, and §32.5 gains its subject.
#   `lifecycle` — the first value that is not knowable at evaluation. It is
#                 already observed rather than hypothetical: two of the twelve
#                 mesh sketches of the corpus, its C2, assign an address only
#                 after the daemon has authenticated, so those two are outside
#                 this folder by construction.
{ korora }:
{
  # The half a consumer may wire. An ed25519 public key is a short line of text
  # that is safe on every machine in the fleet and is the value the other end of
  # a backup edge actually needs.
  publicKeyText = {
    type = korora.string;
    secrecy = "public";
  };

  # The half no slot may read, and the only refusal this folder gets out of
  # `secrecy` alone.
  #
  # The corpus's secrets-per-instance sketch declares `localPrivateKey`
  # too, and the two are NOT the same atom: that one is a quadruple whose
  # `locality = "machine-local"` is what makes the cross-machine read
  # unaskable, and this one has no locality at all. §32.6 requires a folder
  # copying a sibling's declaration to state every field in which the copy
  # differs, so: same name, same type class, same secrecy, and two fewer
  # fields.
  #
  # Without a locality the refusal has to come from somewhere else, and here it
  # comes from one rule stated once: A SLOT'S `reads` MAY NOT NAME AN EXPORT
  # WHOSE `secrecy` IS `secret`. Not "not across a machine boundary" — never. A
  # secret export is declarable so that the pair is visible and the refusal is
  # producible, and it is readable only by the units of the service that made
  # it.
  #
  # That is stronger than the sibling's rule and it costs something real, which
  # ../plan/diagnostics.txt records as a gap rather than as a win: the
  # sibling's `travellingSecret`, a routable secret with no public counterpart,
  # is a shape this folder cannot express. A database password has to reach its
  # consumer, and delivering one needs `per`, `deploy` and a per-consumer
  # delivery set. None of the three is here.
  localPrivateKey = {
    type = korora.secretRef;
    secrecy = "secret";
  };

  repoUrl = {
    type = korora.url;
    secrecy = "public";
  };

  quotaGiB = {
    type = korora.int;
    secrecy = "public";
  };
}
