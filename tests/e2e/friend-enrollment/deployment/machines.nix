# Two machines, and the difference between their addresses is the whole change.
#
# The hub is the operator's own: an address the operator's network resolves,
# root, and the coordination server placed on it. The friend machine is a
# third party's, behind nothing the operator can route to, and its address is
# the name the mesh gives it - so every URL an export builds from
# `target.address` carries that name and whatever answers it is the mesh's
# business. Enrollment adds no registry key: `scope` and the four fields below
# are what a registry already reads.
#
# rookery hands out static dnsmasq leases keyed by MAC address, 10.0.0.10
# upwards in boot order, so the hub's address is not a free choice. The friend
# machine's lease exists too and appears nowhere here, which is the point:
# nothing in this deployment can dial it by a number.
let
  mesh = import ./mesh.nix;
in
{
  machines = {
    hub = {
      address = "10.0.0.10";
      tags = [ "coordinates" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    friend = {
      address = mesh.nameOf "friend";
      tags = [ "friends" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      scope = "user";
    };
  };
}
