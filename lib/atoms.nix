{ korora }:
let
  inherit (builtins) isAttrs isString match;
in
korora
// {
  url = korora.typedef "url" (v: isString v && match "[a-z][0-9a-z+.-]*://[^[:space:]]+" v != null);

  secretRef = korora.typedef "secretRef" (
    v: isAttrs v && v ? path && isString v.path && (v.secrecy or null) == "secret"
  );

  unitRef = korora.typedef "unitRef" (v: isString v && match "[0-9A-Za-z][0-9A-Za-z_.-]*" v != null);

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

  userName = korora.typedef "userName" (
    v: isString v && match "[a-z_][0-9a-z_-]{0,30}[$]?" v != null
  );
}
