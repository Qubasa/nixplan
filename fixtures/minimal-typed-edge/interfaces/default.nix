# An interface is identified by the value an author imports, never by its name.
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

  # Two exports, so that provider keyset equality has something to be equal about.
  borgRepository = korora.interface {
    name = "borg-repository";
    exports = {
      url = e.repoUrl;
      quota = e.quotaGiB;
    };
  };
}
