{
  python3,
  curl,
  page,
  health,
  httpEndpoint,
}:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  claims.ports.http = {
    proto = "tcp";
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
    let
      # A build states the request its probe fetches, or states none and the
      # unit records no probe at all: the two fields are in the entry's key, so
      # a build that declares one is a different artifact than a build that
      # does not.
      probed = health != null;

      # The probe fetches the page over the port this module allocated, so what
      # it asserts is the service and not a marker beside it. The retries are
      # for the start job racing its own listener - `After=` says the unit was
      # started and never that it is listening - and a status the server
      # answers with is no retry, so a request the page does not carry fails at
      # once.
      request = "${curl}/bin/curl --fail --silent --show-error --retry 10 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:${toString alloc.ports.http}${health}";
    in
    {
      closure = [
        python3
        page
      ]
      ++ (if probed then [ curl ] else [ ]);

      provides.page.exports = {
        url = "http://${target.address}:${toString alloc.ports.http}/";
      };

      units.serve = {
        # Binds every address because the unit starts before the DHCP lease exists. The
        # plan is held to the exported URL, which does use the planned address.
        command = "${python3}/bin/python3 -m http.server ${toString alloc.ports.http} --bind 0.0.0.0 --directory ${page}";
      }
      // (
        if probed then
          {
            probe = request;
            # The bound is required beside the probe, and it is longer than the
            # retries above can take so that what stops a failing probe is the
            # request and not the bound.
            probeTimeout = "30s";
          }
        else
          { }
      );
    };
}
