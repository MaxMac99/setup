# k3s cluster membership — the four-node, three-site cluster of Phase 7.
#
# Replaces modules/system/k3s-node.nix, which Phase 6 deleted along with the
# microVMs it existed for. Everything here is derived from
# `networkConfig.hosts.<host>`, so a node's role, site and node IP are stated
# once, as data, in modules/data/network-config.nix.
#
# ## Why one parameterised module and not k3s-server.nix + k3s-agent.nix
#
# 6.2 asked for a split by role. It also asked, in the same breath, to
# "parameterise node role" — which is the opposite instruction, and is the one
# followed here. Of the twelve flags below, agents differ from servers by
# omitting six and adding none: an agent is a strict subset. Splitting would
# duplicate the shared half or need a third module to hold it, and that third
# module already exists — k3s-base.nix, which both roles import for the
# firewall, containerd, sysctls and tooling.
#
# ## What this module deliberately does NOT do
#
# **No local-path provisioner.** k3s-node.nix shipped one, pinned to the
# virtiofs path `/mnt/k8s-fast/local-path-provisioner` that died with the
# microVMs. Rewriting it needs a per-node `nodePathMap`, and the four nodes have
# genuinely different storage (maxdata's `fast` pool, brink-server's `main`,
# winkel-pi's USB-SATA disk, ionos's root). That is Phase 8's subject together
# with D6's site pinning, and Phase 7's gate does not mention storage. Guessing
# it here would ship a manifest that is wrong on three nodes out of four.
{
  config,
  lib,
  ...
}: let
  cfg = config.k3sCluster;
  net = config.networkConfig;
  self = net.hosts.${config.hostSpec.hostName};
  first = net.hosts.${cfg.firstServer};

  isServer = self.k3sRole == "server";
in {
  imports = [(lib.custom.relativeToRoot "modules/system/k3s-base.nix")];

  options.k3sCluster = {
    enable = lib.mkEnableOption "membership of the multi-site k3s cluster";

    clusterInit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this node bootstraps the cluster with `--cluster-init`.

        Exactly one node sets this, and only ever for the *first* start of a
        brand-new cluster. Leaving it set afterwards is harmless — k3s ignores
        it once etcd has a member list — but a second node setting it would
        create a second, silently disjoint cluster.
      '';
    };

    firstServer = lib.mkOption {
      type = lib.types.str;
      default = "ionos";
      description = ''
        `networkConfig.hosts` key of the server every other node joins through.

        ionos by default, because it is the one host with a fixed address and
        the one that is never behind CGNAT — but note this is a *join-time*
        dependency only. Once a server has joined etcd it no longer needs this
        node, so ionos being down does not partition the cluster.
      '';
    };

    tokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "k3s_token";
      description = "Name of the sops secret holding the cluster join token.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--node-taint=edge=true:NoSchedule"];
      description = ''
        Host-specific flags appended to the derived set.

        Kept deliberately small. Anything that is a property of *where a node
        is* belongs in `networkConfig.hosts` and should be derived above, not
        passed here — this exists for genuinely per-host policy, which today
        means only ionos's edge taint.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = self.k3sRole != null;
        message = "k3sCluster: ${config.hostSpec.hostName} has no k3sRole in networkConfig.hosts.";
      }
      {
        # Without this the node silently comes up on its LAN address, which for
        # three of the four nodes is unreachable from the other sites (D3).
        assertion = self.overlayIPv4 != null;
        message = "k3sCluster: ${config.hostSpec.hostName} has no overlayIPv4; --node-ip would be wrong (D3).";
      }
      {
        assertion = cfg.clusterInit -> isServer;
        message = "k3sCluster: only a server can --cluster-init.";
      }
      {
        assertion = first.overlayIPv4 != null;
        message = "k3sCluster: firstServer ${cfg.firstServer} has no overlayIPv4 to join through.";
      }
    ];

    # Point kubectl at the cluster. Without this it falls back to its built-in
    # default of localhost:8080 and fails with "connection refused" or
    # "current-context is not set" — which reads like a broken cluster and is
    # only a missing environment variable. Every previous session that ran
    # kubectl on a node had to export this by hand.
    #
    # ⚠️ Servers only. k3s writes `/etc/rancher/k3s/k3s.yaml` on servers and
    # **not on agents**, so setting this fleet-wide would point winkel-pi at a
    # file that does not exist — trading one confusing error for another.
    # Verified live: the three servers have it at mode 644, winkel-pi has no
    # kubeconfig at all.
    environment.variables.KUBECONFIG = lib.mkIf isServer "/etc/rancher/k3s/k3s.yaml";

    sops.secrets.${cfg.tokenSecret} = {
      sopsFile = lib.custom.relativeToRoot "secrets/k3s.yaml";
      restartUnits = ["k3s.service"];
    };

    services.k3s = {
      role = lib.mkForce self.k3sRole;
      tokenFile = config.sops.secrets.${cfg.tokenSecret}.path;

      # The first server has no one to join. Everyone else joins through it.
      serverAddr = lib.mkIf (!cfg.clusterInit) "https://${first.overlayIPv4}:6443";

      extraFlags = lib.mkForce (toString (
        [
          "--node-name=${config.hostSpec.hostName}"

          # D3: the overlay is the only address family all four nodes share.
          # Two of them are behind CGNAT at different sites and ionos has no
          # LAN at all, so a LAN node-ip is not merely suboptimal, it is
          # unroutable from most of the cluster.
          "--node-ip=${self.overlayIPv4}"

          # ⚠️ This is how the MTU gets pinned — there is **no `--flannel-mtu`
          # flag**, verified against k3s v1.35.6 (`k3s server --help` matches
          # zero MTU options). Flannel derives its MTU from this interface
          # minus the backend's overhead, so naming the interface is the only
          # lever, and naming the *wrong* one is D3's blackhole: large payloads
          # vanish while ping still succeeds.
          #
          # tailscale0 measures **1280** on all four nodes, so flannel.1 must
          # come up at **1230** (VXLAN −50). That is a prediction to check, not
          # an assumption — the old cluster is the control: it rode wg0 at MTU
          # 1420 and its flannel.1 was 1370, exactly 1420 − 50.
          "--flannel-iface=${config.services.tailscale.interfaceName}"

          # D5/D6 schedule by site; `public` rather than the old `external`,
          # to match the networkConfig.sites keys.
          "--node-label=topology.kubernetes.io/zone=${self.site}"
        ]
        ++ lib.optionals isServer [
          "--disable=servicelb" # MetalLB owns LoadBalancer (D5)
          "--disable=traefik" # Traefik is Pulumi-managed (D7)
          "--disable=local-storage" # storage is Phase 8's subject
          "--write-kubeconfig-mode=644"
          "--tls-san=${config.hostSpec.hostName}"
          "--tls-san=${self.overlayIPv4}"

          # D1: IPv4 only. The dual-stack CIDRs this replaces existed solely so
          # ionos could reach home under DS-Lite; the overlay does that now.
          "--cluster-cidr=10.42.0.0/16"
          "--service-cidr=10.43.0.0/16"

          # D4, from measurement rather than folklore: Phase 2 sampled p99
          # 6.8 ms direct and 23–25 ms relayed over 347 samples per direction.
          # 500/5000 sits 73× and 735× above that p99. Defaults (100/1000)
          # cause spurious leader elections across two consumer uplinks.
          "--etcd-arg=heartbeat-interval=500"
          "--etcd-arg=election-timeout=5000"
        ]
        ++ lib.optionals cfg.clusterInit ["--cluster-init"]
        ++ cfg.extraFlags
      ));
    };
  };
}
