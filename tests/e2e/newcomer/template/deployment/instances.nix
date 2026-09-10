{ hello }:
{
  instances = {
    greeter = {
      module = hello.services.default;
      placement.every.greet = {
        tags = [ "greets" ];
      };
    };
  };
}
