# The modules this repository publishes for a consumer to compose, as outputs.
# A path inside this flake's source is not an interface, which is why
# `flake.operator` is published rather than pointed at, and it is why these are
# too: a module reachable only as a file of this checkout is a module a
# deployment outside it cannot name, and a module inside an end-to-end folder is
# one nothing outside that folder may name at all.
#
# Each is under a name whose namespace says which kind it is: a deployment
# composes a planner module into an instance, and a machine's own configuration
# imports a machine module. Both are functions of the facts they refuse to
# default, so a consumer who states none fails their own evaluation naming the
# argument.
{
  # The coordination server a deployment places: the membership authority of a
  # mesh, as an entry of a plan.
  flake.plannerModules.coordination = import ./coordination;

  # The one-time root work a machine needs before a run can write to it as the
  # account it deploys as.
  flake.nixosModules.provisioning = import ./provisioning;
}
