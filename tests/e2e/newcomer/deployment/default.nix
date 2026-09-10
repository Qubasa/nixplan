# The deployment of this folder is the one its template holds, so `nix build
# .#planner-e2e-newcomer` builds by hand what a machine of the walk builds for
# itself. The test builds neither: it copies the template onto a machine and runs
# every step there.
args: {
  default = import ../template/deployment args;
}
