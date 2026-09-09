# rookery hands out static dnsmasq leases keyed by MAC address, 10.0.0.10 upwards
# in boot order. These are not free-choice test addresses.
{
  machines = {
    alpha = {
      address = "10.0.0.10";
      tags = [ "issues" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    beta = {
      address = "10.0.0.11";
      tags = [ "reads" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    # In the cluster, in neither instance, and in no delivery set. That is what it
    # is for: the negative claim is machine-scoped.
    gamma = {
      address = "10.0.0.12";
      tags = [ "idles" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
