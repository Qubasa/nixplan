{ korora }:
{
  reportFile = korora.interface {
    name = "report-file";
    exports = {
      path = {
        type = korora.string;
        secrecy = "public";
      };

      # The generated file the watching entry owns, published as a reference:
      # bytes in an export would be a leak, and a path is what a reader opens.
      secret = {
        type = korora.secretRef;
        secrecy = "secret";
      };
    };
  };
}
