# A static file server, and the one module in this repository whose published
# value cannot be rendered without knowing where it is running.
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

      # The address is the machine the planner placed this service on, read out
      # of the target. It is declared once, in ../../machines.nix.
      provides.page.exports = {
        url = "http://${target.address}:${toString alloc.ports.http}/";
      };

      # Bound on every address rather than on `target.address`: the unit starts
      # before the DHCP lease exists, and a socket that fails to bind once is a
      # boot ordering fact about the guest rather than anything about the plan.
      # What the plan is held to is the URL above, which the consumer dials.
      units.serve = {
        command = "${python3}/bin/python3 -m http.server ${toString alloc.ports.http} --bind 0.0.0.0 --directory ${page}";
      };
    };
}
