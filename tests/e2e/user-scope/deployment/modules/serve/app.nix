{ serveScript }:

_: {
  platforms = [ "x86_64-linux" ];

  # A value with no ownership stated at all. A user scope honours no stated
  # owner and no stated group - the delivery writes the file as the account it
  # connects as and can chown it to nobody, which is
  # `value-ownership-in-user-scope` - so this declares neither, and the account
  # the run connects as is the account the unit runs as, which is why the unit
  # can open it.
  vars.served = {
    per = "instance";
    files.token = {
      secrecy = "secret";
    };
  };

  # No `user`, no `supplementaryGroups` and no port: a unit declaring an account
  # in user scope is `unit-account-in-user-scope`, a unit declaring groups is
  # `unit-groups-in-user-scope`, and a user manager grants neither. The
  # confinement that needs no privilege is the profile's and is not degraded.
  impl =
    {
      instance,
      member,
      vars,
      ...
    }:
    let
      # Derived here, from the identity of this entry, so a second entry of this
      # module on one machine writes its own record: the service manager deletes
      # a runtime directory when its unit restarts, and a shared one would take
      # the other's with it.
      name = "${instance}-${member}";
    in
    {
      # The script alone. Its own wrapper resolves what it runs, so naming a
      # package here would be a closure root the entry mentions nowhere.
      closure = [ serveScript ];

      units.serve = {
        command = "${serveScript}/bin/planner-user-scope-serve";
        env = {
          # The value's own path, which the library derives and no declaration
          # states: the fixed roots do not move with the scope.
          TOKEN_FILE = vars.served.token.path;
          RECORD_NAME = "record";
        };
        # The record goes under the directory the account's own manager creates
        # for this unit, which is the only directory a user-scope unit is handed
        # without asking root for one.
        runtimeDirectory = [ name ];
      };
    };
}
