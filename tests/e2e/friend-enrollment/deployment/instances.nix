# Two instances: the membership authority the operator runs, and the third
# party's own service on the machine that authority admitted. They are wired to
# nothing - enrollment is an order of work, not a composition - and the second
# one knows nothing about the first.
#
# The first is the module this repository publishes, composed rather than
# copied, so the four choices this cluster makes are settings stated here
# instead of lines of a module's text. Each is a choice about a network with no
# route to anybody else's, which is exactly why a published module may not make
# it: the listener, the relay, its client verification and the empty relay map
# are what an offline cluster of two machines needs, and the node expiry of
# zero is what keeps a run that takes minutes from being a run in which a
# member aged out.
{ coordination, guestapp }:
let
  mesh = import ./mesh.nix;
in
{
  instances = {
    mesh = {
      module = coordination;

      settings.hub = {
        # Both machines reach the server over the cluster LAN, and the unit
        # starts before the lease exists, so the listener is every interface
        # and the clients are told the address the registry declares.
        listenAddress = "0.0.0.0";

        # The relay is the server's own, and its map is the only one: these
        # clients reach no network of anybody else's, so a public relay list
        # would be a name no guest resolves. Verification is the server asking
        # that relay whether a presenter is a node it admitted, and these
        # clients have no route to it at all - they find each other directly
        # over the network the cluster gives them, and the region exists only
        # because an empty map is refused.
        embeddedRelay = true;
        verifyClients = false;
        relayUrls = [ ];

        # Membership ends when the operator expels a node and at no other
        # moment.
        nodeExpiry = "0";

        inherit (mesh) port stunPort;
      };

      placement.every.hub = {
        tags = [ "coordinates" ];
      };
    };

    guestapp = {
      module = guestapp;
      placement.every.run = {
        tags = [ "friends" ];
      };
    };
  };
}
