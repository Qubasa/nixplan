{ korora }:
{
  publicKeyText = {
    type = korora.string;
    secrecy = "public";
  };

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
