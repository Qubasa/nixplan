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
