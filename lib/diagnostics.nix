# The diagnostics table: records, ordering, subject discipline and rendering.
#
# Rows are values that callers return alongside their result. There is no
# accumulator and no ambient list, because either would be a second way for a
# row to exist and a check nothing enforces is the defect this library is about.
{ util }:
let
  inherit (builtins)
    any
    concatStringsSep
    filter
    isString
    match
    sort
    ;

  severities = [
    "error"
    "warning"
  ];

  # A subject is a plan key, a path relative to the deployment root, or an issue
  # identifier. An absolute path is refused because it would make a rendered
  # table differ between two checkouts.
  isPlanKey = s: match "[0-9A-Za-z_.-]+:[0-9A-Za-z_.-]+(@[0-9A-Za-z_.-]+)?" s != null;
  isIssueId = s: match "universe-[0-9a-z]+" s != null;
  isPathSubject = s: match "[0-9A-Za-z_./-]+\\.nix" s != null && util.isRelativePath s;
in
rec {
  inherit severities;

  isValidSubject = s: isString s && (isPlanKey s || isIssueId s || isPathSubject s);

  # A row. Every field is required: a row with no resolution is a row a person
  # cannot act on. The subject is left exactly as given here and disciplined in
  # `mkTable`, so that a bad subject produces a row instead of being hidden.
  row =
    {
      id,
      subject,
      severity,
      message,
      evidence,
      resolution,
    }:
    {
      inherit id subject severity;
      message = util.oneLine message;
      evidence = util.oneLine evidence;
      resolution = util.oneLine resolution;
    };

  error = args: row (args // { severity = "error"; });
  warning = args: row (args // { severity = "warning"; });

  # Forcing a module's own expression. tryEval catches a throw and a failed
  # assert; it does not catch an abort or a missing attribute, which is why the
  # library documents those as propagating rather than claiming to contain them.
  guard =
    {
      subject,
      what,
      fallback,
      value,
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
            inherit subject;
            id = "module-raised";
            message = "${what} raised a catchable error, so its value is recorded as not computed";
            evidence = "the planner forced the value inside `builtins.tryEval` and produced the rest of the plan";
            resolution = "fix the expression in the module file that produced ${what}";
          })
        ];
      };

  # A row about a row. The offending subject is reduced to its last path
  # component and this names the id that carried it, so the absolute path never
  # reaches the table.
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
  # cannot turn one bad atom into two problems.
  # `listToAttrs` keeps the first of two rows with one key, and an attribute
  # set costs a lookup rather than a copy of everything seen so far.
  dedup =
    rows:
    builtins.attrValues (
      builtins.listToAttrs (
        map (r: {
          name = util.joinLines [
            r.id
            r.subject
            r.message
          ];
          value = r;
        }) rows
      )
    );

  # Ordering is by identifier then subject then message, so two evaluations of
  # one input render byte for byte the same table however the rows arose. A
  # subject is judged once: the row it produces and the reduction of its own
  # subject are two uses of one answer.
  mkTable =
    rows:
    let
      judged = map (r: {
        row = r;
        ok = isValidSubject r.subject;
      }) rows;
      invalid = filter (j: !j.ok) judged;
      disciplined =
        map (j: if j.ok then j.row else j.row // { subject = util.baseNameOfString j.row.subject; }) judged
        ++ map (j: subjectRow j.row) invalid;
    in
    sort (
      a: b:
      if a.id != b.id then
        a.id < b.id
      else if a.subject != b.subject then
        a.subject < b.subject
      else
        a.message < b.message
    ) (dedup disciplined);

  hasError = table: any (r: r.severity == "error") table;

  # The row format the example folders already use. A function of the table
  # alone: rendering never reads the deployment again.
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
