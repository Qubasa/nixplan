# rookery hands out static dnsmasq leases keyed by MAC address, 10.0.0.10 upwards
# in boot order. These are not free-choice test addresses.
#
# Two machines rather than three: alpha holds the shared cluster, the consumer of
# one of its databases and the application that owns a second cluster of the same
# module; beta the consumer of the other database. Co-location, two instances on
# one machine and a routable read are all present at two, and beta is a working
# consumer that is outside one delivery set, which is the negative claim a machine
# running nothing cannot make.
{
  machines = {
    alpha = {
      address = "10.0.0.10";
      tags = [
        "database"
        "near"
        "private"
      ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    beta = {
      address = "10.0.0.11";
      tags = [ "far" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
