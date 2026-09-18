# The engine `planner-lemmalog` loads this repository's invariant facts into.
# Upstream publishes no flake, so the revision and the two hashes are pinned here
# rather than taken as an input: a tool the shell carries is a tool this
# repository pins.
{
  fetchFromGitHub,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "lemmalog";
  version = "0.2.0-unstable-2026-08-28";

  src = fetchFromGitHub {
    owner = "JordyZomer";
    repo = "lemmalog";
    rev = "b8e24dbd80df61b7c6f1757dd77342a6228a6f84";
    hash = "sha256-lh88fdpxnBxit0cBSBdAQI5cO6sgLqkw9bcnwxe90dc=";
  };

  cargoHash = "sha256-6XNsbyzVcVljrOMXmemSDzKjYdEFZ+a9/GY8myy+iPY=";

  # `lemmalog-cli` and `lemmalog-mcp` both declare this feature as required, and
  # the model-backed half is not one this repository asks for.
  buildFeatures = [ "mcp" ];

  doCheck = false;
}
