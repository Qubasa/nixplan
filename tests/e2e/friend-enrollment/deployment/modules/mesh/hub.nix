# The coordination server, as a planned entry rather than as guest-image
# wiring: the membership authority is itself a service the plan places, which
# is the whole reason this folder's hub is a machine of the deployment and not
# a fact of the image. The image only carries the packages.
#
# Everything the server needs at a host path is derived here from the identity
# of this entry - its own instance and member - so two of it on one machine
# would hold two databases and neither would be a path this deployment states.
{ headscale, mintProgram }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  # The API port clients present a credential to, and the port the server
  # answers NAT-traversal probes on. Fixed rather than defaulted, because the
  # URL the clients are configured with is built from the same number and a
  # mesh whose members dial another port is no mesh.
  claims.ports.api = {
    proto = "tcp";
    fixed = settings.port;
  };

  claims.ports.stun = {
    proto = "udp";
    fixed = settings.stunPort;
  };

  # The join credential. It is a generated value like any other: single-use and
  # expiring because the server owns both refusals, secret because it is bearer
  # authority until it is spent, and delivered to no machine - the operator
  # reads it out of the value source and hands it over outside the tree. The
  # entry still records the file, which is why a plan carries `deploy` at all:
  # nothing binds the path of a value no machine holds.
  vars.enrollment = {
    per = "instance";
    deploy = false;
    program = mintProgram;
    files.preauthkey.secrecy = "secret";
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

      # The server's own state: its database, the key it encrypts client
      # traffic with and the key its relay identifies itself by. Declared
      # rather than made, so the service manager owns the directory for the
      # unit and this deployment states no path of the machine.
      stateName = "headscale/${name}";
      stateDir = "/var/lib/${stateName}";
      configPath = "/etc/${name}/config.yaml";

      port = toString alloc.ports.api;
      stun = toString alloc.ports.stun;

      # What the clients are told to dial, built from the address the registry
      # declares for this machine. The mesh names the server serves live under
      # a domain of their own, which the server refuses to have as a suffix of
      # this URL: the clients take that domain over.
      url = "http://${target.address}:${port}";

      configuration = [
        "server_url: ${url}"
        "listen_addr: 0.0.0.0:${port}"
        # An empty value disables the listener. Nothing here reads metrics, and
        # a port nothing reads is a claim this entry would owe the machine.
        ''metrics_listen_addr: ""''
        "grpc_listen_addr: 127.0.0.1:50443"
        "grpc_allow_insecure: false"
        "noise:"
        "  private_key_path: ${stateDir}/noise_private.key"
        "prefixes:"
        "  v4: 100.64.0.0/10"
        "  v6: fd7a:115c:a1e0::/48"
        "  allocation: sequential"
        # The relay is the server's own, and its map is the only one: the
        # cluster reaches no network of anybody else's, so a public relay list
        # would be a name no guest can resolve. The server refuses to start on
        # an empty map, which is why the embedded region is added to it.
        "derp:"
        "  server:"
        "    enabled: true"
        "    region_id: 999"
        "    region_code: planner"
        "    region_name: planner embedded relay"
        "    stun_listen_addr: 0.0.0.0:${stun}"
        "    private_key_path: ${stateDir}/derp_server_private.key"
        "    automatically_add_embedded_derp_region: true"
        # The relay verifies no client, because verification is the server
        # asking its own relay whether a presenter is a node it admitted, and
        # the clients here are nodes with no route to the relay at all: they
        # discover each other directly over the network the cluster gives them
        # and the region exists only because an empty map is refused.
        "    verify_clients: false"
        "  urls: []"
        "  paths: []"
        "  auto_update_enabled: false"
        "  update_frequency: 24h"
        "disable_check_updates: true"
        "node:"
        # No default expiry: membership ends when the operator expires a node
        # and at no other moment, so a run that takes minutes cannot be a run
        # in which a node aged out.
        "  expiry: 0"
        "  ephemeral:"
        "    inactivity_timeout: 30m"
        "  routes:"
        "    ha:"
        "      probe_interval: 10s"
        "      probe_timeout: 5s"
        "database:"
        "  type: sqlite"
        "  sqlite:"
        "    path: ${stateDir}/db.sqlite"
        "    write_ahead_log: true"
        "log:"
        "  level: info"
        "  format: text"
        "policy:"
        "  mode: file"
        # Escaped rather than written as an indented string: nix strips the
        # common indentation of one of those, so `''  path: ""''` renders a
        # top-level `path` and the policy loses the only key it states.
        "  path: \"\""
        "dns:"
        "  magic_dns: true"
        "  base_domain: ${settings.domain}"
        # The members keep the resolver they already have and are handed the
        # mesh domain beside it: an offline guest whose resolver was replaced
        # would lose the names its own cluster answers for.
        "  override_local_dns: false"
        "  nameservers:"
        "    global: []"
        "  search_domains: []"
        "  extra_records: []"
        "unix_socket: ${stateDir}/headscale.sock"
        ''unix_socket_permission: "0770"''
        "logtail:"
        "  enabled: false"
        ""
      ];
    in
    {
      closure = [ headscale ];

      # A file of literals, so its bytes are the plan's and the artifact
      # carries them. The record is the one a store object carries, stated
      # rather than defaulted, because the realiser that binds store objects
      # installs nothing and would refuse any other.
      configData.${configPath} = {
        owner = "root";
        group = "root";
        mode = "0444";
        render = [ { text = builtins.concatStringsSep "\n" configuration; } ];
      };

      units.serve = {
        command = "${headscale}/bin/headscale --config ${configPath} serve";
        stateDirectory = [ stateName ];
        stateDirectoryMode = "0700";
        # The authority a fleet keeps: a crash is the service manager's to
        # recover from rather than the next apply's.
        restart = "on-failure";
        restartSec = "1s";
      };
    };
}
