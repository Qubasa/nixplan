{
  python3,
  issueScript,
  mintProgram,
  deriveProgram,
  attestation,
}:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  claims.ports.http = {
    proto = "tcp";
    count = 1;
    fixed = settings.port;
  };

  vars = {
    # The root of the chain. Nobody receives it: it exists for the value below to
    # be derived from, which is what `deploy = false` says.
    root = {
      per = "instance";
      deploy = false;
      program = mintProgram;
      files.key.secrecy = "secret";
    };

    # One value for the instance, so the consumer on another machine presents the
    # bytes this machine checks against. Its public half is a digest of its secret
    # half, so a plan carrying one and a machine holding the other can be compared.
    token = {
      per = "instance";
      program = deriveProgram;
      reads = [ "root" ];
      files = {
        secret.secrecy = "secret";
        fingerprint.secrecy = "public";
      };
    };
  };

  provides.api = {
    interface = attestation;
  };

  impl =
    {
      target,
      alloc,
      vars,
      ...
    }:
    {
      closure = [
        python3
        issueScript
      ];

      provides.api.exports = {
        url = "http://${target.address}:${toString alloc.ports.http}/";
        secret = vars.token.secret;
        fingerprint = vars.token.fingerprint.content;
      };

      units.serve = {
        # Binds every address because the unit starts before the DHCP lease exists.
        # The plan is held to the exported URL, which does use the planned address.
        command = "${python3}/bin/python3 ${issueScript} ${toString alloc.ports.http}";
        env.TOKEN_FILE = vars.token.secret.path;
      };
    };
}
