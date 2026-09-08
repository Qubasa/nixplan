# rookery hands out static dnsmasq leases keyed by MAC address, 10.0.0.10 upwards
# in boot order. These are not free-choice test addresses.
{
  machines = {
    alpha = {
      address = "10.0.0.10";
      tags = [ "serves" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    beta = {
      address = "10.0.0.11";
      tags = [ "fetches" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
