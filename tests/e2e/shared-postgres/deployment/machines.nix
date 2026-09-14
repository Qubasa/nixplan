# rookery hands out static dnsmasq leases keyed by MAC address, 10.0.0.10 upwards
# in boot order. These are not free-choice test addresses.
#
# Two machines rather than three: alpha holds the cluster and the consumer of one
# database, beta the consumer of the other. Co-location and a routable read are
# both present at two, and beta is a working consumer that is outside one
# delivery set, which is the negative claim a machine running nothing cannot make.
{
  machines = {
    alpha = {
      address = "10.0.0.10";
      tags = [
        "database"
        "near"
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
