# The type layer: korora's own types plus the atoms this library needs and korora
# has no name for. verify is the only entry point used anywhere here, because
# korora's raising validator would end an evaluation this library keeps total.
{ korora, util }:
let
  inherit (builtins)
    elem
    head
    isAttrs
    isInt
    isString
    match
    ;

  # The domain of every atom that is an enumeration, so the row that reports a
  # value outside one can name what it may take. Read by `lib/module.nix`.
  restartPolicies = [
    "no"
    "on-failure"
    "on-abnormal"
    "always"
  ];

  # Which service manager runs a machine's units, and so which privilege a
  # deployment onto it may spend. Root is the account every check admits, so the
  # domain is two values and not a mode: `system` is the manager root runs and
  # `user` is the account's own.
  scopes = [
    "system"
    "user"
  ];

  # How many slots may be wired to one provided capability. `many` is what a
  # capability declaring nothing means, so the domain carries it rather than
  # leaving the default unnameable.
  consumerCardinalities = [
    "one"
    "many"
  ];

  # What a port claim may listen on. Two values rather than the four systemd
  # carries: the other two need a kernel module and appear in no unit here, and
  # widening the domain later is additive.
  protocols = [
    "tcp"
    "udp"
  ];

  # The range a port is an integer of, read by the atom and by the row that
  # reports a value outside it, with the first port an account may bind without
  # a capability root holds. The boundary rides the range because it is a fact
  # about the same domain, and the row about a privileged claim in a user scope
  # reads it here.
  portRange = {
    first = 1;
    last = 65535;
    privilegedBelow = 1024;
  };

  # The wildcard is the absence of a claim's address and never a spelling of it.
  # Two spellings of one reading is what let one number be claimed twice, so the
  # shape is refused rather than a list of literals: an address drawn from `0`,
  # `.` and `:` alone is all-zeros in both families, `::ffff:` in front of one is
  # the same address v4-mapped, and `inet_aton` reads a bare hex zero as one too.
  # A zone names an interface and narrows nothing about the address, so it is
  # dropped before the comparison.
  isWildcardAddress =
    v:
    let
      zoned = match "([^%]*)%.*" v;
      bare = if zoned == null then v else head zoned;
    in
    match "[0.:]+" bare != null
    || match "::[fF][fF][fF][fF]:[0.:]+" bare != null
    || match "0[xX]0+" bare != null;
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

  # Which durations spell no bound at all. The type keeps admitting zero -
  # `timeout` and `restartSec` may legitimately state it, and narrowing the type
  # would re-key every plan that does - so the reading that refuses a zero is
  # handed the spelling instead. The magnitudes are the only digits a duration
  # carries, so it spells zero exactly when it carries no nonzero digit, written
  # as the absence of one rather than as a list of literals: the type admits any
  # concatenation, so `0`, `0s`, `0min` and `0s0min` are all of them and `0s1s`
  # is none.
  #
  # A predicate in a table of value domains keyed by korora type name is not a
  # mistake: it rides an existing key because a new top-level key on the right of
  # the update below costs one copied value per plan, which the gate has no room
  # for, and `isZeroDuration` is a name no atom carries, so the field-type row's
  # lookup by type name cannot reach it.
  domains.isZeroDuration = v: isString v && match "[^1-9]*" v != null;

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

  # What a service manager does when a unit stops. Four values rather than
  # systemd's seven: the other three are meaningless without a `Type=` or a
  # `WatchdogSec=` this vocabulary does not carry. The atom is the planner's own
  # domain, so a realiser maps it to its manager's spelling.
  restartPolicy = korora.typedef "restartPolicy" (v: isString v && elem v restartPolicies);

  domains.restartPolicy = restartPolicies;

  # The privilege a machine offers a deployment. The domain is the whole type:
  # unstated means `system`, no module or interface declares a scope, and the one
  # reading that crosses a stated value against it is the registry's, so the list
  # is the single home and a korora typedef over it would be a second one.
  domains.scope = scopes;

  # Whether a provided capability may be taken by one slot or by any number. A
  # provider states it; no deployment can widen it.
  consumerCardinality = korora.typedef "consumerCardinality" (
    v: isString v && elem v consumerCardinalities
  );

  domains.consumerCardinality = consumerCardinalities;

  # A port as a deployment states it. Zero is refused with the rest of the range:
  # asking the kernel to choose is the excluded allocation table under another
  # spelling, and a number written as text is not the number it spells.
  port = korora.typedef "port" (v: isInt v && v >= portRange.first && v <= portRange.last);

  inherit portRange;

  # The protocol a port claim listens on. A claim stating none is read as every
  # protocol of the domain, which is the comparison that is safe by default.
  protocol = korora.typedef "protocol" (v: isString v && elem v protocols);

  domains.protocol = protocols;

  # The single address a listener binds: a dotted quad, a v6 address with its
  # zone, or a name, because which of them a machine answers on is the machine's
  # answer. A wildcard spelling is refused, the absence saying it already.
  bindAddress = korora.typedef "bindAddress" (
    v: isString v && match "[0-9A-Za-z:._%-]+" v != null && !isWildcardAddress v
  );

  # A delivered file's permission bits as a deployment states them: four octal
  # digits, the spelling `install -m` and `chmod` both take. A symbolic mode is
  # refused because two writers render it and neither parses one.
  fileMode = korora.typedef "fileMode" (v: isString v && match "[0-7][0-7][0-7][0-7]" v != null);

  # An account name for an owner or a group, held to the same grammar a unit's
  # `user` is: which identity it resolves to is the machine's answer.
  groupName = korora.typedef "groupName" (
    v: isString v && match "[a-z_][0-9a-z_-]{0,30}[$]?" v != null
  );

  # A portable account name rather than a uid: which identity a name resolves to is
  # the machine's answer, not the plan's.
  userName = korora.typedef "userName" (
    v: isString v && match "[a-z_][0-9a-z_-]{0,30}[$]?" v != null
  );

  # A directory a service manager creates for a unit, named relative to the root
  # its kind implies. A name stating a root of its own fails this rather than
  # earning an identifier: the kind decides where the directory lives.
  directoryName = korora.typedef "directoryName" (
    v: isString v && match "[0-9A-Za-z_][0-9A-Za-z_.-]*(/[0-9A-Za-z_][0-9A-Za-z_.-]*)*" v != null
  );

  # A path on the machine as a unit states it. Relative resolves against nothing
  # a plan records, and whitespace is what a directive line cannot carry.
  absolutePath = korora.typedef "absolutePath" (v: isString v && match "/[^[:space:]]*" v != null);

  # The public half of the identity a machine opens its own sealed values with,
  # as the registry declares it. The grammar is `util.ageRecipientRule`, stated
  # beside the word grammar it is a subset of, the way `restartPolicy` reads
  # `restartPolicies`: the atom and the row that reports a refused line read one
  # home, and a rendered step carries the recipient as an ordinary word.
  ageRecipient = korora.typedef "ageRecipient" (
    v: isString v && match util.ageRecipientRule v != null
  );
}
