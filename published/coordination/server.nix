# The leaf module of a coordination server: the entry a deployment places to own
# the membership of a mesh. Every fact a cluster chooses is a settings knob whose
# default this module can defend outside one; the two facts it refuses to choose
# at all - the url a client is configured with and who is admitted - are
# arguments of the module beside it, so a composing root that states neither
# fails its own evaluation rather than receiving a value nobody meant.
#
# What the operator's own verbs read is a store object of this entry's closure:
# the object is named so the server's own loader accepts it, and the program is
# handed it as its first argument. Both are named in the deployment's
# `coordinate` statement and resolved against this entry's closure, so a verb
# reproduces no rule of this module's.
{
  admin,
  configurationOf,
  configurationName,
  clientUrl,
  stateName,
  policyClosure,
  writeText,
}:

{ settings, ... }:
{
  platforms = settings.platforms;

  # The port clients present a credential to. Fixed rather than defaulted,
  # because the url the clients are configured with is built from the same
  # number and a mesh whose members dial another port is no mesh.
  claims.ports = {
    api = {
      proto = "tcp";
      fixed = settings.port;
    };
  }
  // (
    if settings.embeddedRelay then
      {
        stun = {
          proto = "udp";
          fixed = settings.stunPort;
        };
      }
    else
      { }
  );

  # The join credential. A generated value like any other: single-use and
  # expiring because the server owns both refusals, secret because it is bearer
  # authority until it is spent, and delivered to no machine - the operator
  # reads it out of the value source and hands it over outside the tree. The
  # entry still records the file, which is why a plan carries `deploy` at all.
  #
  # The expiry rides beside it as a public file, because what a credential was
  # minted under is a fact the operator is told and no byte of the key.
  vars.enrollment = {
    per = "instance";
    deploy = false;
    program = admin.mint;
    files.preauthkey.secrecy = "secret";
    files.expiry.secrecy = "public";
  };

  impl =
    {
      instance,
      member,
      target,
      alloc,
      ...
    }:
    let
      name = "${instance}-${member}";

      # The one path this entry states that is its own rather than the mesh's.
      # It exists inside the serving unit's namespace alone, which is why the
      # operator's own invocations read the store object below instead.
      configPath = "/etc/planner-coordination/${name}/config.yaml";

      url = clientUrl {
        inherit (target) address;
        port = alloc.ports.api;
      };

      text = configurationOf {
        inherit settings url;
        port = alloc.ports.api;
      };

      # The object an administrative invocation reads, from the same text as the
      # bytes the plan holds, so the two cannot disagree: the serving unit reads
      # a declared file the realiser binds, and a bound store object is named by
      # a digest with no suffix, which the server's own loader refuses because it
      # decides a configuration's format from the extension. This one carries it.
      #
      # It is a closure root nothing mentions, which the planner records as a
      # warning: the operator's verbs read it and no unit does.
      configuration = writeText configurationName text;
    in
    {
      # Three roots, and the second one is the one a reader trips over: a
      # generator's program is recorded in the plan and is deliberately no
      # closure root and no mention site, so an entry that did not declare it
      # would be an entry the copy never puts it on - and the verb that mints
      # runs it on that machine and would refuse forever, naming an apply as
      # what puts it there. Declaring it earns `closure-root-unmentioned`,
      # which is the honest record: the operator's own verbs run these two and
      # no unit of this entry does.
      closure = [
        admin.program
        admin.mint
        "${configuration}"
      ]
      ++ policyClosure;

      configData.${configPath} = {
        owner = "root";
        group = "root";
        mode = "0444";
        render = [ { inherit text; } ];
      };

      units.serve = {
        command = "${admin.program} serve ${configPath}";
        stateDirectory = [ stateName ];
        stateDirectoryMode = "0700";
        # The authority a fleet keeps: a crash is the service manager's to
        # recover from rather than the next apply's.
        restart = "on-failure";
        restartSec = "1s";
      };
    };
}
