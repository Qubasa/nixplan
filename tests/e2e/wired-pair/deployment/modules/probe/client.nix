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
        # The retries are for cross-machine boot ordering, not for flakiness. Nothing
        # orders one guest's socket against another guest's client.
        command = "${curl}/bin/curl --fail --silent --show-error --retry 5 --retry-connrefused --retry-delay 2 --max-time 10 --output ${settings.recordPath} ${results.upstream.url}";
        # Oneshot and remaining after exit, so "the request succeeded" is a unit state. The
        # body is recorded so a redelivery can show a different answer.
        oneShot = true;
        remainAfterExit = true;
      };
    };
}
