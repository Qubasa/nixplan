# The far end of the wire: it fetches what it was handed and records the body.
#
# The URL it dials is not a setting, not a hostname it composes and not a
# machine name it knows. It is the value the provider published, resolved at
# evaluation, delivered into this unit's command as a string.
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

      # A oneshot that stays active on success, so "the request succeeded" is a
      # unit state the machine reports rather than a file a test has to
      # interpret. The body is recorded too, because a redelivery has to be able
      # to show a different answer from the same request.
      #
      # The retries are about boot ordering rather than flakiness: after a reboot
      # of both machines there is no ordering between one machine's socket and
      # another machine's client, and a fetch that gives up on the first refused
      # connection would report a wire that is resolved as a wire that is down.
      units.fetch = {
        command = "${curl}/bin/curl --fail --silent --show-error --retry 5 --retry-connrefused --retry-delay 2 --max-time 10 --output ${settings.recordPath} ${results.upstream.url}";
        oneShot = true;
        remainAfterExit = true;
      };
    };
}
