{
  python3,
  page,
  httpEndpoint,
}:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  claims.ports.http = {
    proto = "tcp";
    count = 1;
    fixed = settings.port;
  };

  provides.page = {
    interface = httpEndpoint;
  };

  impl =
    {
      target,
      alloc,
      ...
    }:
    {
      closure = [
        python3
        page
      ];

      provides.page.exports = {
        url = "http://${target.address}:${toString alloc.ports.http}/";
      };

      units.serve = {
        # Binds every address because the unit starts before the DHCP lease exists. The
        # plan is held to the exported URL, which does use the planned address.
        command = "${python3}/bin/python3 -m http.server ${toString alloc.ports.http} --bind 0.0.0.0 --directory ${page}";
      };
    };
}
