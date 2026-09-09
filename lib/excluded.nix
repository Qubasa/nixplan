# The exclusion table of fixtures/minimal-typed-edge/README.md, as data. A
# deployment writing one of these keys gets an error row naming the construct and
# the trigger that would bring it back. row is the README row the construct
# belongs to, so a test can assert that every row of that table is refused.
{
  rows = [
    "locality"
    "lifecycle"
    "placement.pick/strategy/allocation"
    "member cuts"
    "externals"
    "collect family"
    "runtime plane"
  ];

  constructs = {
    locality = {
      row = "locality";
      trigger = "the first export in the target whose value is a unix socket path or a loopback port, at which point machine-local is a fact about an object rather than a policy";
    };
    lifecycle = {
      row = "lifecycle";
      trigger = "the first value that is not knowable at evaluation; two of the twelve mesh sketches of the corpus this folder came out of assign an address only after the daemon authenticates";
    };
    pick = {
      row = "placement.pick/strategy/allocation";
      trigger = "the first service whose machine the operator is willing to let the planner choose";
    };
    strategy = {
      row = "placement.pick/strategy/allocation";
      trigger = "the first service whose machine the operator is willing to let the planner choose";
    };
    dynamicPort = {
      row = "placement.pick/strategy/allocation";
      trigger = "a persisted allocation table, so that a port chosen without a recorded claim does not move on the next evaluation and re-key the entry that claimed it";
    };
    enable = {
      row = "member cuts";
      trigger = "a module publishing a composition whose coherent cuts an operator wants";
    };
    memberWire = {
      row = "member cuts";
      trigger = "a module publishing a composition whose coherent cuts an operator wants";
    };
    externals = {
      row = "externals";
      trigger = "a non-fleet resource this deployment has to name, which the corpus records as U3 and U4 and neither is closed";
    };
    collects = {
      row = "collect family";
      trigger = "clanServices/pki and nothing smaller: a slot whose far end is every service on the reader's machine";
    };
    contributes = {
      row = "collect family";
      trigger = "clanServices/pki and nothing smaller: a slot whose far end is every service on the reader's machine";
    };
    answers = {
      row = "collect family";
      trigger = "clanServices/pki and nothing smaller: a slot whose far end is every service on the reader's machine";
    };
    probes = {
      row = "runtime plane";
      trigger = "not this change: probes presuppose the fact register and the watch contract";
    };
    register = {
      row = "runtime plane";
      trigger = "not this change: the register, the frontier and the host agent are the runtime plane";
    };
    frontier = {
      row = "runtime plane";
      trigger = "not this change: the register, the frontier and the host agent are the runtime plane";
    };
    orchestrator = {
      row = "runtime plane";
      trigger = "not this change: the register, the frontier and the host agent are the runtime plane";
    };
  };
}
