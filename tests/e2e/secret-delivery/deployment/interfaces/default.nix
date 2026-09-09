{ korora }:
{
  tokenEndpoint = korora.interface {
    name = "token-endpoint";
    exports = {
      url = {
        type = korora.url;
        secrecy = "public";
      };

      # A reference and never a value: the plan carries the name of the secret and
      # the delivery carries the bytes.
      token = {
        type = korora.secretRef;
        secrecy = "secret";
      };

      caCert = {
        type = korora.string;
        secrecy = "public";
      };
    };
  };
}
