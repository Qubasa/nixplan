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
