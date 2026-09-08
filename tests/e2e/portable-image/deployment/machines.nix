# The two machines this deployment is planned for, and the only file holding
# either address.
#
# One of them boots: `alpha` is the guest the run starts, at the address rookery
# leases VM 0 (`rookery/qemu/spec.py:61-62,110-122`). `elsewhere` is declared as
# an aarch64 machine and never booted - it exists so the plan places an entry on
# a machine this host is not, and the image built for it can be carried to the
# machine that is and refused there.
{
  machines = {
    alpha = {
      address = "10.0.0.10";
      tags = [ "attaches" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    elsewhere = {
      address = "10.0.0.11";
      tags = [ "elsewhere" ];
      system = "aarch64-linux";
      serviceManager = "systemd";
    };
  };
}
