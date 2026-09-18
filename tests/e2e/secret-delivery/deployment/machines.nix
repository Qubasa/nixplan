# rookery hands out static dnsmasq leases keyed by MAC address, 10.0.0.10 upwards
# in boot order. These are not free-choice test addresses.
#
# Every machine declares the same seal recipient, which is the public line of
# the throwaway identity committed beside this deployment as
# throwaway-age-identity.txt and installed on each machine by the folder's first
# phase. gamma declares one and receives no value, which is what proves the
# unsealer follows the delivery set rather than the placement.
{
  machines = {
    alpha = {
      address = "10.0.0.10";
      tags = [ "issues" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      sealRecipient = "age1cdlaxew5ephl6zcwm3cxnzscwsgeqjmy7543alp33muctvd98uaq3x2ec3";
    };

    beta = {
      address = "10.0.0.11";
      tags = [ "reads" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      sealRecipient = "age1cdlaxew5ephl6zcwm3cxnzscwsgeqjmy7543alp33muctvd98uaq3x2ec3";
    };

    # In the cluster, in neither instance, and in no delivery set. That is what it
    # is for: the negative claim is machine-scoped.
    gamma = {
      address = "10.0.0.12";
      tags = [ "idles" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      sealRecipient = "age1cdlaxew5ephl6zcwm3cxnzscwsgeqjmy7543alp33muctvd98uaq3x2ec3";
    };
  };
}
