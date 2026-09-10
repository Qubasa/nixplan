{ greeter }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  # The greeting names the machine the entry was planned for, so the two entries of
  # one instance are two artifacts rather than one copied twice.
  impl =
    { target, ... }:
    {
      closure = [ greeter ];

      units.say = {
        command = "${greeter}/bin/greet";
        env.GREET_WHO = settings.who;
        env.GREET_WHERE = target.address;
        env.GREET_PATH = settings.greetingPath;
      };
    };
}
