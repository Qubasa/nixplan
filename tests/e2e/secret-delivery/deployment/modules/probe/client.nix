{
  python3,
  checkScript,
  tokenEndpoint,
}:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  uses.api = {
    interface = tokenEndpoint;
    reach = "one";
    # Naming `token` here is what puts this machine in that value's delivery set.
    # Nothing else can derive it: a routable secret is bounded by nobody, and
    # `impl` runs after wiring.
    reads = [
      "url"
      "token"
      "caCert"
    ];
  };

  impl =
    { results, ... }:
    {
      closure = [
        python3
        checkScript
      ];

      units.fetch = {
        command = "${python3}/bin/python3 ${checkScript}";
        env = {
          API_URL = results.api.url;
          # A secret export resolves to its reference record, so the path is asked
          # for by name. Interpolating the export itself raises.
          TOKEN_FILE = results.api.token.path;
          CA_CERT = results.api.caCert;
          RECORD_PATH = settings.recordPath;
        };
        # Oneshot and remaining after exit, so "the credential worked" is a unit state.
        oneShot = true;
        remainAfterExit = true;
      };
    };
}
