# Two interfaces, four exports, and one edge in each direction between two
# instances. That is the whole type surface of the folder.
#
# An interface is the value an author imports through lexical closure and never
# a name resolved at composition time (§32.6). This folder leans on that harder
# than its siblings do, because the thing it is measured against is a registry:
# clan-core validates a produced export against a closed list of six interfaces
# it owns (`modules/clan/top-level-interface.nix:421-427`), so an interface
# nobody upstreamed cannot be produced at all. The case is on record —
# `machine.nix.substituters` does not exist and five independent implementations
# write it anyway (the corpus's unaddressed register, C1..C4, and
# its binary-caches sketch states the same finding from the cache side).
# Replacing the registry with a value is the same move §28.2 made and it is
# free: `name` below is a diagnostic label with no matching authority, and every
# row in ../plan/diagnostics.txt renders the declaring file beside it.
#
# Neither interface here shares a name with a sibling's, so §32.6's collision
# warning is stated and unexercised in this folder.
{ korora }:
let
  e = import ./exports.nix { inherit korora; };
in
{
  # One object with two halves, declared together. The argument is
  # the corpus's secrets-per-instance sketch's and it is worth restating
  # only because the mechanism differs: there, `publicCert` is wirable and
  # `privateKey` is capped `machine-local`, and the cap is what makes the leak
  # unwritable. Here there is no cap and the pair is refused by the secrecy rule
  # in ./exports.nix instead.
  #
  # Both halves have a reader in this folder, which is the condition an export
  # has to meet to stay. `publicKey` is read across an instance boundary by
  # ../modules/borg-repo/server.nix. `privateKey` is read by
  # ../modules/borg-push/client.nix, and not through a slot: the client is the
  # service that made the key and its own unit takes the path. That is the
  # distinction the secrecy rule turns on, and it is why this folder needs no
  # export declared purely to make a row producible.
  sshHostIdentity = korora.interface {
    name = "ssh-host-identity";
    exports = {
      publicKey = e.publicKeyText;
      privateKey = e.localPrivateKey;
    };
  };

  # What a repository offers a pusher. Two exports rather than one, so that
  # keyset equality has something to be equal about: a provider publishing
  # `url` and not `quota` is a row, and so is a provider publishing a third
  # export, and no superset satisfies this interface. That refusal is the one
  # clan-core cannot state at all, because a consumer there reads whatever
  # happens to be in a flat attrset and writes `or [ ]` when it is not.
  #
  # `quota` is a number the repository owns and the pusher obeys. It is here
  # rather than in the pusher's settings because the value is the server's fact
  # about its own disk, and a setting on the client would be three copies of one
  # number maintained by hand — which is the shape the corpus's firewall sketch refuses
  # for `from = "mesh:vpn-core"` one level up.
  borgRepository = korora.interface {
    name = "borg-repository";
    exports = {
      url = e.repoUrl;
      quota = e.quotaGiB;
    };
  };
}
