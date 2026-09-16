# The diagnostics table. A row is a value a caller returns beside its result.
# There is no accumulator and no ambient list, because either would be a second
# way for a row to exist.
{ util }:
let
  inherit (builtins)
    any
    concatStringsSep
    elem
    filter
    isString
    match
    sort
    ;

  severities = [
    "error"
    "warning"
  ];

  # A subject is a plan key the planner built, a path relative to the deployment
  # root, or an issue identifier. An absolute path is refused, because a rendered
  # table would then differ between two checkouts.
  #
  # A plan key is stated by its structure and not by the characters its names
  # happen to carry: a name is held to `util.unkeyableName` and nothing else, so
  # every key the planner builds from a name that rule admits is a subject. A
  # component may be empty here, because a name the rule refused earns its own
  # row and the key the planner built from it is still the subject that row
  # names.
  keyName = "[^@:/[:cntrl:]]*";
  isPlanKey = s: match "${keyName}:(vars/)?${keyName}(@${keyName})?" s != null;
  isIssueId = s: match "universe-[0-9a-z]+" s != null;
  isPathSubject = s: match "[0-9A-Za-z_./-]+\\.nix" s != null && util.isRelativePath s;
in
rec {
  inherit severities;

  isValidSubject = s: isString s && (isPlanKey s || isIssueId s || isPathSubject s);

  # Every field is required. A row with no resolution is a row nobody can act on.
  # The subject goes through `oneLine` beside the three fields below it, so a
  # rendered table has one line per field whatever a deployment interpolated into
  # a name.
  row =
    {
      id,
      subject,
      severity,
      message,
      evidence,
      resolution,
    }:
    if !(elem severity severities) then
      severityRow { inherit id subject severity; }
    else
      {
        inherit id severity;
        subject = util.oneLine subject;
        message = util.oneLine message;
        evidence = util.oneLine evidence;
        resolution = util.oneLine resolution;
      };

  # A severity outside the domain is reported where the row is built, so no
  # reading has to infer it by comparing the value against the error spelling.
  severityRow =
    {
      id,
      subject,
      severity,
    }:
    error {
      inherit subject;
      id = "diagnostic-severity-invalid";
      message = "row ${util.quote id} was built with a severity of ${util.shownValue severity}, and a row carries one of ${util.quoteList severities}";
      evidence = "the row it was built with is replaced by this one, so nothing in the table carries a severity no producer may state";
      resolution = "build the row with `error` or `warning` where it is produced";
    };

  error = args: row (args // { severity = "error"; });
  warning = args: row (args // { severity = "warning"; });

  # Forcing a module's own expression. tryEval catches a raise and a failed
  # assertion. It catches neither an abort nor a missing attribute, which is why
  # those two are documented as propagating.
  guard =
    {
      subject,
      what,
      fallback,
      value,
      id ? "module-raised",
    }:
    let
      attempt = builtins.tryEval (builtins.deepSeq value value);
    in
    if attempt.success then
      {
        value = attempt.value;
        rows = [ ];
      }
    else
      {
        value = fallback;
        rows = [
          (error {
            inherit subject id;
            message = "${what} raised a catchable error, so its value is recorded as not computed";
            evidence = "the planner forced the value inside `builtins.tryEval` and produced the rest of the plan";
            resolution = "fix the expression in the module file that produced ${what}";
          })
        ];
      };

  subjectRow =
    r:
    error {
      id = "diagnostic-subject-invalid";
      subject = util.baseNameOfString r.subject;
      message = "row ${util.quote r.id} carries a subject that is not a plan key, a deployment-relative path or an issue identifier";
      evidence = "the subject was reduced to its last path component so that a rendered table does not differ between checkouts";
      resolution = "give the row a plan key, a path relative to the deployment root, or an issue identifier where it is produced under lib/";
    };

  # The same fact produced twice is one row: two modules reading one interface
  # cannot turn one bad atom into two problems. listToAttrs keeps the first.
  dedup =
    rows:
    builtins.attrValues (
      util.mapToAttrs (r: {
        name = util.joinLines [
          r.id
          r.subject
          r.message
        ];
        value = r;
      }) rows
    );

  # Ordered by identifier, then subject, then message, so two evaluations of one
  # input render the same bytes however the rows arose.
  #
  # Deduplication reads the rows as their producers built them, before the repair
  # below it: two facts about two files whose names agree in their last component
  # are two rows, and collapsing them would tell a reader about one declaration.
  # The rows the repair earns are deduplicated among themselves, one repaired
  # subject being one fact about one table.
  mkTable =
    rows:
    let
      judged = map (r: {
        row = r;
        ok = isValidSubject r.subject;
      }) (dedup rows);
      invalid = filter (j: !j.ok) judged;
      disciplined =
        map (j: if j.ok then j.row else j.row // { subject = util.baseNameOfString j.row.subject; }) judged
        ++ dedup (map (j: subjectRow j.row) invalid);
    in
    sort (
      a: b:
      if a.id != b.id then
        a.id < b.id
      else if a.subject != b.subject then
        a.subject < b.subject
      else
        a.message < b.message
    ) disciplined;

  hasError = table: any (r: r.severity == "error") table;

  renderRow =
    r:
    util.joinLines [
      "  ! ${r.subject}  ${r.message}"
      "      severity: ${r.severity}"
      "      evidence: ${r.evidence}"
      "      resolution: ${r.resolution}"
    ];

  render = table: concatStringsSep "\n\n" (map renderRow table);
}
