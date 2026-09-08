{
  machines = {
    # authorizes, and this folder has no field to narrow a `reach = "all"` set.
    vault = {
      address = "vault.example";
      tags = [ "always-on" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    alpha = {
      address = "alpha.example";
      tags = [
        "always-on"
        "backed-up"
      ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    beta = {
      address = "beta.example";
      tags = [
        "always-on"
        "backed-up"
      ];
      system = "aarch64-linux";
      serviceManager = "systemd";
    };

    gamma = {
      address = "gamma.example";
      tags = [ "backed-up" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
