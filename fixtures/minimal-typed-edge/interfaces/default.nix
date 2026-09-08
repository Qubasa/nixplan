# An interface is the value an author imports through lexical closure and never
{ korora }:
let
  e = import ./exports.nix { inherit korora; };
in
{
  sshHostIdentity = korora.interface {
    name = "ssh-host-identity";
    exports = {
      publicKey = e.publicKeyText;
      privateKey = e.localPrivateKey;
    };
  };

  borgRepository = korora.interface {
    name = "borg-repository";
    exports = {
      url = e.repoUrl;
      quota = e.quotaGiB;
    };
  };
}
