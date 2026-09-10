{ korora }:
{
  attestation = korora.interface {
    name = "attestation";
    exports = {
      url = {
        type = korora.url;
        secrecy = "public";
      };

      # A reference and never a value: the plan names the file and the deploy step
      # of the generator carries the bytes.
      secret = {
        type = korora.secretRef;
        secrecy = "secret";
      };

      # The public half of the same generated value, which is a digest of the
      # secret. It travels in the plan, and only once the value exists.
      fingerprint = {
        type = korora.string;
        secrecy = "public";
      };
    };
  };
}
