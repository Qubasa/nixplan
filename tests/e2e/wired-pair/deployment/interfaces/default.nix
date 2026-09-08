{ korora }:
{
  httpEndpoint = korora.interface {
    name = "http-endpoint";
    exports = {
      url = {
        type = korora.url;
        secrecy = "public";
      };
    };
  };
}
