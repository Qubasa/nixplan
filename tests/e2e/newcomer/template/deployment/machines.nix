{
  machines = {
    alpha = {
      address = "10.0.0.11";
      tags = [ "greets" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    beta = {
      address = "10.0.0.12";
      tags = [ "greets" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
