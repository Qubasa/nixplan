# The names the mesh answers for, read by both halves of this folder: the
# registry declares the friend machine by the name the mesh gives it, and the
# coordination server's own configuration states the domain those names live
# under. One file, because a registry address and a server's base domain that
# disagree are a machine nothing can dial.
#
# `nameOf` is applied to a machine's own registry key, so a mesh name is
# derived from the deployment's own machine names rather than written twice.
rec {
  # The domain the coordination server serves. It is not the server's own host
  # - the server refuses a base domain that is a suffix of its URL, because the
  # clients take the domain over - so nothing here resolves it but the mesh.
  domain = "planner-mesh.internal";

  # The port the server listens on and the port it answers NAT-traversal
  # probes on. Both are claims of the entry that runs it.
  port = 8080;
  stunPort = 3478;

  # The name the server groups admitted machines under. The credential this
  # deployment declares belongs to it, which is what makes the node list the
  # operator reads after a join the answer about one group of machines.
  group = "friends";

  # How long a minted credential admits anybody. Stated here because it is a
  # declaration and not an operator's whim at mint time: every credential
  # `planner invite` mints carries this figure, so the deployment and not the
  # invocation decides it.
  #
  # Two minutes, because this folder spends both halves of that one figure. A
  # credential has to outlive its own handover - minted by the verb, read out
  # of the value source, presented on the other machine, and then presented a
  # second time by a throwaway node so the server can refuse a spent key - and
  # the folder also has to outlive one, presenting a credential the server
  # refuses for being past it. A cluster declaring an hour could prove the
  # first and would have to sleep an hour to prove the second; one declaring a
  # handful of seconds would be racing its own handover.
  expiry = "120s";

  nameOf = machine: "${machine}.${domain}";
}
