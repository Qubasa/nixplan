{ korora }:
{
  reportFile = korora.interface {
    name = "report-file";
    exports = {
      path = {
        type = korora.string;
        secrecy = "public";
      };
    };
  };
}
