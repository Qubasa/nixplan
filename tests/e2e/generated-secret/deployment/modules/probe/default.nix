{
  python3,
  attestScript,
  attestation,
}:

{ service, ... }:
{
  services.client = service "client" {
    module = import ./client.nix { inherit python3 attestScript attestation; };
    defaults.recordPath = "/run/generated-secret-attest.json";
  };
}
