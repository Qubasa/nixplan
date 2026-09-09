{
  python3,
  serveScript,
  tokenEndpoint,
}:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  claims.ports.http = {
    proto = "tcp";
    count = 1;
    fixed = settings.port;
  };

  vars = {
    # One value for the instance, not one per machine: the consumer on another
    # machine has to present the same bytes the provider checks against.
    session = {
      per = "instance";
      files.token = {
        secrecy = "secret";
      };
    };

    # One value, and no machine receives bytes. Its public half travels in the
    # plan as a value, which is what a consumer reads.
    ca = {
      per = "instance";
      deploy = false;
      files."ca.pub" = {
        secrecy = "public";
      };
    };
  };

  provides.api = {
    interface = tokenEndpoint;
  };

  impl =
    {
      target,
      alloc,
      vars,
      ...
    }:
    {
      closure = [
        python3
        serveScript
      ];

      provides.api.exports = {
        url = "http://${target.address}:${toString alloc.ports.http}/";
        token = vars.session.token;
        caCert = vars.ca."ca.pub".content;
      };

      units.serve = {
        # Binds every address because the unit starts before the DHCP lease exists. The
        # plan is held to the exported URL, which does use the planned address.
        command = "${python3}/bin/python3 ${serveScript} ${toString alloc.ports.http}";
        env.TOKEN_FILE = vars.session.token.path;
      };
    };
}
