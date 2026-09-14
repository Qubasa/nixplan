{
  curl,
  httpEndpoint,
}:

_: {
  platforms = [ "x86_64-linux" ];

  uses.upstream = {
    interface = httpEndpoint;
    reach = "one";
    reads = [ "url" ];
  };

  impl =
    {
      instance,
      member,
      results,
      ...
    }:
    let
      # Derived from the entry's own identity, so two of these on one machine
      # record two bodies rather than overwriting each other.
      record = "/run/${instance}-${member}.body";
    in
    {
      closure = [ curl ];

      units.fetch = {
        # The retries are for cross-machine boot ordering, not for flakiness. Nothing
        # orders one guest's socket against another guest's client.
        command = "${curl}/bin/curl --fail --silent --show-error --retry 5 --retry-connrefused --retry-delay 2 --max-time 10 --output ${record} ${results.upstream.url}";
        # Oneshot and remaining after exit, so "the request succeeded" is a unit state. The
        # body is recorded so a redelivery can show a different answer.
        oneShot = true;
        remainAfterExit = true;
      };
    };
}
