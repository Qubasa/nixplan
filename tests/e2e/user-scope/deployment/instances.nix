# One instance on one machine. The whole of what this folder declares is an
# entry an account attaches and a value that account is handed, because what it
# proves is the scope and not a composition.
{ serve }:
{
  instances = {
    serve = {
      module = serve.services.default;
      placement.every.app = {
        tags = [ "accounts" ];
      };
    };
  };
}
