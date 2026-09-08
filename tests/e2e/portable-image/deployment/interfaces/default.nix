# One interface: the path on a machine at which one entry keeps the file it
# assembled, read by an entry planned for a different machine.
#
# The wire exists so this deployment has two entries that know about each other
# while only one of them can ever attach: the other is planned for a machine of
# another architecture, which is what the refusal is asserted against.
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
