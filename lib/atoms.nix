# The type layer: korora's own types plus the atoms this library needs and korora
# has no name for. verify is the only entry point used anywhere here, because
# korora's raising validator would end an evaluation this library keeps total.
{ korora }:
let
  inherit (builtins) isAttrs isString match;
in
korora
// {
  url = korora.typedef "url" (v: isString v && match "[a-z][0-9a-z+.-]*://[^[:space:]]+" v != null);

  # A reference to a secret, never its bytes: a path, a secrecy and whether the
  # generator has run. There is deliberately no content field.
  secretRef = korora.typedef "secretRef" (
    v: isAttrs v && v ? path && isString v.path && (v.secrecy or null) == "secret"
  );

  # The name of a unit. The reader refuses a name the referring module did not
  # declare itself, so a module cannot order itself against a stranger's unit.
  unitRef = korora.typedef "unitRef" (v: isString v && match "[0-9A-Za-z][0-9A-Za-z_.-]*" v != null);

  # systemd's spelling. A binding that needs seconds converts rather than the
  # vocabulary guessing.
  duration = korora.typedef "duration" (
    v: isString v && match "([0-9]+(ns|us|ms|s|m|min|h|d|w))+|[0-9]+" v != null
  );

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

  # A portable account name rather than a uid: which identity a name resolves to is
  # the machine's answer, not the plan's.
  userName = korora.typedef "userName" (
    v: isString v && match "[a-z_][0-9a-z_-]{0,30}[$]?" v != null
  );
}
