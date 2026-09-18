# One machine, deployed as an account rather than as root. `scope` is the only
# thing that says so: the account is the login the run connects as, which is a
# fact of the run and not of the registry, and every other field is the field a
# system-scope machine states.
{
  machines = {
    alpha = {
      address = "10.0.0.10";
      tags = [ "accounts" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      scope = "user";
    };
  };
}
