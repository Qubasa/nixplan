{
  python3,
  attestScript,
  attestation,
}:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  uses.api = {
    interface = attestation;
    reach = "one";
    # Naming `secret` here is what puts this machine in that value's delivery set.
    # The public `fingerprint` is deliberately not read: a unit's environment is
    # rendered before anything has been generated, so the digest is compared
    # against the plan rather than handed to a machine.
    reads = [
      "url"
      "secret"
    ];
  };

  impl =
    { results, ... }:
    {
      closure = [
        python3
        attestScript
      ];

      units.attest = {
        command = "${python3}/bin/python3 ${attestScript}";
        env = {
          API_URL = results.api.url;
          # A secret export resolves to its reference record, so the path is asked
          # for by name. Interpolating the export itself raises.
          TOKEN_FILE = results.api.secret.path;
          RECORD_PATH = settings.recordPath;
        };
        # Oneshot and remaining after exit, so "the credential worked" is a unit state.
        oneShot = true;
        remainAfterExit = true;
      };
    };
}
