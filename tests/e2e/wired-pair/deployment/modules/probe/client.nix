{
  curl,
  httpEndpoint,
}:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  uses.upstream = {
    interface = httpEndpoint;
    reach = "one";
    reads = [ "url" ];
  };

  impl =
    { results, ... }:
    {
      closure = [ curl ];

      units.fetch = {
        command = "${curl}/bin/curl --fail --silent --show-error --retry 5 --retry-connrefused --retry-delay 2 --max-time 10 --output ${settings.recordPath} ${results.upstream.url}";
        oneShot = true;
        remainAfterExit = true;
      };
    };
}
