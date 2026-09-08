# alpha is the booted guest. elsewhere is aarch64 and never booted, so that an
# image can be built for a machine this host is not.
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
