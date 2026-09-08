# The type layer. korora's own primitives, plus the atom types the folder and
# the unit vocabulary write that korora has no name for, so that
# fixtures/minimal-typed-edge/interfaces/exports.nix is evaluable exactly
# as written.
#
# `verify` is the only entry point used anywhere in this library. `check`
# raises, and a test greps this tree for it.
{ korora }:
let
  inherit (builtins) isAttrs isString match;
in
korora
// {
  # A scheme, "://" and something after it. The folder's `repoUrl` binds to
  # this and its value is ssh://borg@host:port/path.
  url = korora.typedef "url" (v: isString v && match "[a-z][0-9a-z+.-]*://[^[:space:]]+" v != null);

  # A reference to a secret rather than its bytes. The value is the vars file
  # record the planner hands a module: a path, a secrecy and whether the
  # generator has run. There is deliberately no `content` in it.
  secretRef = korora.typedef "secretRef" (
    v: isAttrs v && v ? path && isString v.path && (v.secrecy or null) == "secret"
  );

  # A reference to a unit. The value is the name of a unit, and the reader
  # refuses a name the referring module did not declare itself, which is what
  # keeps a module from ordering itself against a stranger's unit.
  unitRef = korora.typedef "unitRef" (v: isString v && match "[0-9A-Za-z][0-9A-Za-z_.-]*" v != null);

  # A span of time: one or more counts with a unit, or a bare count of seconds.
  # The spelling is systemd's and launchd has no spelling of its own, so a
  # binding that needs seconds converts rather than the vocabulary guessing.
  duration = korora.typedef "duration" (
    v: isString v && match "([0-9]+(ns|us|ms|s|m|min|h|d|w))+|[0-9]+" v != null
  );

  # When a unit runs without anything asking it to: a named interval, or a
  # calendar expression with an optional weekday and an optional date.
  schedule = korora.typedef "schedule" (
    v:
    isString v
    && (
      match "minutely|hourly|daily|weekly|monthly|quarterly|semiannually|yearly" v != null
      ||
        match "([A-Z][a-z][a-z](,[A-Z][a-z][a-z])* )?([0-9*]+-[0-9*]+-[0-9*]+ )?[0-9*]{1,2}:[0-9*]{1,2}(:[0-9*]{1,2})?" v
        != null
    )
  );

  # The account a unit runs as. Portable across the service managers in
  # charter, so it is the POSIX-portable name and not a uid: the identity a
  # name resolves to is the machine's answer and not the plan's.
  userName = korora.typedef "userName" (
    v: isString v && match "[a-z_][0-9a-z_-]{0,30}[$]?" v != null
  );
}
