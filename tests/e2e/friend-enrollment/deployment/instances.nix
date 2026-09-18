# Two instances: the membership authority the operator runs, and the third
# party's own service on the machine that authority admitted. They are wired to
# nothing - enrollment is an order of work, not a composition - and the second
# one knows nothing about the first.
{ mesh, guestapp }:
{
  instances = {
    mesh = {
      module = mesh.services.default;
      placement.every.hub = {
        tags = [ "coordinates" ];
      };
    };

    guestapp = {
      module = guestapp.services.default;
      placement.every.run = {
        tags = [ "friends" ];
      };
    };
  };
}
