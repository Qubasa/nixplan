# rookery hands out static dnsmasq leases keyed by MAC address, 10.0.0.10 upwards
# in boot order. These are not free-choice test addresses.
{
  machines = {
    alpha = {
      address = "10.0.0.10";
      tags = [ "attests" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    beta = {
      address = "10.0.0.11";
      tags = [ "verifies" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    # In the cluster, in neither instance, and in no delivery set.
    gamma = {
      address = "10.0.0.12";
      tags = [ "waits" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
