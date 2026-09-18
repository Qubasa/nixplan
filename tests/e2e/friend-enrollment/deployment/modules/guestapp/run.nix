# The third party's own service: one unit on a machine no run could dial
# before it was a member, deployed as an account rather than as root. Nothing
# about it is enrollment-aware - it is an ordinary entry of a machine whose
# scope is `user` - which is the claim: after admission the machine is a
# machine like any other.
{ runScript }:

_: {
  platforms = [ "x86_64-linux" ];

  # No `user`, no `supplementaryGroups` and no port: where the scope is `user`
  # a unit declaring an account is a planner refusal, so is one declaring
  # groups, so is a fixed port below the privileged boundary, and an account's
  # own service manager grants none of the three.
  impl =
    {
      instance,
      member,
      target,
      ...
    }:
    let
      # Derived from the identity of this entry, so a second entry of this
      # module on one machine writes its own record: the service manager
      # deletes a runtime directory when its unit restarts.
      name = "${instance}-${member}";
    in
    {
      closure = [ runScript ];

      units.run = {
        command = "${runScript}/bin/planner-friend-enrollment-run";
        env = {
          # The name the operator's runs dial this machine by, which the
          # registry declared and the planner put in the entry's target. A unit
          # that writes it back is what shows the name reached the machine
          # rather than an address somebody resolved on the way.
          DIALLED_NAME = target.address;
          RECORD_NAME = "record";
        };
        # The record goes under the directory the account's own manager creates
        # for this unit, which is the only directory a unit under that manager
        # is handed without asking root for one.
        runtimeDirectory = [ name ];
      };
    };
}
