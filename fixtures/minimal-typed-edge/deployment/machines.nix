{
  machines = {
    # Holds the repository and is not backed up by it, so it carries no
    # `backed-up` tag and publishes no host identity in this deployment. That
    # keeps the set-valued read at exactly the three machines it is about: a tag
    # this machine also carried would put the server's own key in the set it
    # authorizes, and this folder has no field to narrow a `reach = "all"` set.
    # ../plan/diagnostics.txt records that as a gap rather than hiding it behind
    # a tag choice.
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

    # Newly added, and its keypair has not been generated yet. Every other
    # machine here is uninteresting; this one is the whole reason the folder has
    # a warning row. Under the fold clan-core writes today it drops out of the
    # authorized set silently and the operator finds out when a backup does not
    # happen.
    gamma = {
      address = "gamma.example";
      tags = [ "backed-up" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
