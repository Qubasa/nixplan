# One interface: an HTTP endpoint one machine serves and another fetches.
#
# One export, because the whole point of this deployment is that the export is
# rendered from a fact only the planner holds - the address of the machine the
# provider was placed on - and read on a different machine as a string.
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
