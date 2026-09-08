# The two machines of the cluster, and the only file in this deployment that
# holds either address.
#
# rookery leases VM `i` the address `10.0.0.(10 + i)` from a MAC-keyed static
# dnsmasq reservation (`rookery/qemu/spec.py:61-62,110-122`), so these are the
# addresses the cluster really hands out and a plan written against them is a
# plan the machines can be held to.
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
