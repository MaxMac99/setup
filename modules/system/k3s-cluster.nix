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
  pkgs,
  ...
}: let
  cfg = config.k3sCluster;
  net = config.networkConfig;
  cluster = net.cluster;
  self = net.hosts.${config.hostSpec.hostName};
  first = net.hosts.${cfg.firstServer};

  isServer = self.k3sRole == "server";
  dual = cluster.dualStack;

  # The MTU flannel must hand to pod veths and to its own VXLAN devices.
  #
  # Not `overlay.mtu − 50`, which is what flannel would derive on its own, and
  # the 20-byte difference is the whole reason this is pinned. The VTEPs are
  # `fd7a:` addresses, so the outer header is IPv6 (40 bytes) rather than IPv4
  # (20), and flannel's `encapOverhead` constant is hardcoded to 50 with no
  # notion of the address family it is encapsulating in. Left alone it hands
  # out an MTU 20 bytes larger than tailscale0 can carry, and the packets that
  # fall in that gap are exactly the full-size ones — D3's blackhole, where
  # ping succeeds and bulk transfer dies.
  flannelMTU = net.overlay.mtu - 70;

  # ⚠️ Supplying this replaces k3s's *entire* generated net-conf.json, so the
  # pod CIDRs have to be restated here — and if these disagree with the
  # `--cluster-cidr` flag below, flannel and the controller-manager allocate
  # from different ranges and pods come up unroutable. Both derive from
  # `networkConfig.cluster`, which is what makes that impossible by
  # construction; do not inline a literal into either one.
  #
  # `Backend.MTU` is pre-subtraction: flannel takes this value and subtracts 50
  # to get the device and pod MTU, so it is written as flannelMTU + 50.
  flannelConf = pkgs.writeText "flannel-net-conf.json" (builtins.toJSON {
    Network = cluster.podCidrV4;
    IPv6Network = cluster.podCidrV6;
    EnableIPv4 = true;
    EnableIPv6 = true;
    Backend = {
      Type = "vxlan";
      MTU = flannelMTU + 50;
    };
  });
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

    lanInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "eno1";
      description = ''
        LAN interface on which this server also accepts the Kubernetes API.

        Null means overlay-only, which is the default and is what 7.1
        established: `k3s-base.nix` scopes 6443 to the overlay interface, so a
        laptop on the same LAN as a node still cannot reach the API.

        Setting this opens **6443 only** — not the kubelet or either etcd port —
        on the named interface, and adds this host's `lanIPv4` to the API
        server's TLS SANs. Both halves are required: without the SAN, kubectl
        reaches the port and then fails certificate validation, because k3s
        issues the serving cert for the node names and overlay addresses only.

        ⚠️ **This exposes a cluster-admin API to every device on that LAN**,
        including IoT devices. Access still requires a client certificate, so
        it is not open, but it is a wider surface than the overlay-only default.
        Deliberate trade: direct access from inside a site, overlay when
        outside it.
      '';
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
      {
        assertion = dual -> self.overlayIPv6 != null;
        message = "k3sCluster: cluster.dualStack is on but ${config.hostSpec.hostName} has no overlayIPv6. Read it off the live tailnet (`tailscale ip -6`, or `headscale nodes list` on ionos) and record it in networkConfig.hosts — do not guess it from the v4 assignment.";
      }
      {
        # The whole dual-stack design rests on this one inequality, so it is
        # checked rather than trusted. flannel-v6.1 is created at
        # `flannelMTU`, and the kernel refuses to put an IPv6 address on any
        # device below IPV6_MIN_MTU = 1280 — it returns -EINVAL, or tears
        # existing IPv6 down on a live MTU change. Flannel then fails at
        # `EnsureV6AddressOnLink` and the v6 half of the cluster never comes
        # up, while the v4 half works perfectly and hides it.
        assertion = dual -> flannelMTU >= 1280;
        message = "k3sCluster: cluster.dualStack needs networkConfig.overlay.mtu >= 1350 (it is ${toString net.overlay.mtu}), which puts flannel-v6.1 at ${toString flannelMTU} — below the kernel's IPv6 minimum of 1280, so it cannot hold an address.";
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

    # In-site direct access to the API, opt-in per host via lanInterface.
    #
    # Deliberately **6443 only**. k3s-base.nix puts 6443, 10250, 2379 and 2380
    # on the overlay interface; the kubelet and both etcd ports have no business
    # on a LAN and stay overlay-only, so this widens exactly one port rather
    # than re-opening the set 7.1 just closed.
    networking.firewall.interfaces = lib.mkIf (isServer && cfg.lanInterface != null) {
      ${cfg.lanInterface}.allowedTCPPorts = [6443];
    };

    sops.secrets.${cfg.tokenSecret} = {
      sopsFile = lib.custom.relativeToRoot "secrets/k3s.yaml";
      restartUnits = ["k3s.service"];
    };

    # ⚠️ Ordering, not a preference. Flannel reads the external interface's MTU
    # **once, at startup**, and derives every device and pod MTU from what it
    # sees. If k3s wins the race against overlay-mtu.service it reads 1280,
    # sizes flannel-v6.1 at 1230, and the kernel then refuses that device an
    # IPv6 address — a dual-stack cluster that comes up single-stack, with the
    # working v4 half masking the failure.
    #
    # Cross-module by unit name: the unit is defined in overlay-client.nix,
    # which this module does not import. That coupling is deliberate but
    # invisible, so it is named here rather than assumed.
    systemd.services.k3s = {
      after = ["overlay-mtu.service"];
      wants = ["overlay-mtu.service"];
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
          #
          # D17 lists both families here, and **IPv4 stays first deliberately**.
          # The kubelet always treats the first address as the primary family,
          # and k3s warns explicitly that a v6-primary cluster needs every
          # member's node-ip set with the v6 address leading. Keeping v4 primary
          # means every existing Service, every `100.64.0.x` reference in
          # homelab-k8s and Home Assistant's `trusted_proxies` keep meaning what
          # they mean today; IPv6 is additive rather than a reinterpretation.
          "--node-ip=${
            if dual
            then "${self.overlayIPv4},${self.overlayIPv6}"
            else self.overlayIPv4
          }"

          # Which interface flannel encapsulates over. There is **no
          # `--flannel-mtu` flag**, verified against k3s v1.35.6 (`k3s server
          # --help` matches zero MTU options), so under single-stack this is
          # also the only MTU lever: flannel takes this interface's MTU minus
          # the backend overhead. Naming the *wrong* interface is D3's
          # blackhole — large payloads vanish while ping still succeeds.
          #
          # Single-stack: tailscale0 at 1280 gives flannel.1 at 1230 (VXLAN
          # −50), confirmed live on all four nodes, and cross-checked against
          # the old cluster which rode wg0 at 1420 with flannel.1 at 1370.
          #
          # Dual-stack: inheritance is no longer good enough and the MTU is
          # pinned explicitly below — see `flannelMTU`.
          "--flannel-iface=${config.services.tailscale.interfaceName}"

          # D5/D6 schedule by site; `public` rather than the old `external`,
          # to match the networkConfig.sites keys.
          "--node-label=topology.kubernetes.io/zone=${self.site}"
        ]
        ++ lib.optionals dual [
          # ✅ Confirmed present in **both** `k3s server --help` and `k3s agent
          # --help` at v1.35.6+k3s1, checked on winkel-pi itself (2026-08-12).
          # k3s documents this as a *Flannel Agent Option* — per node, specific
          # to that node's flannel instance — so it belongs here, on every
          # node, rather than in the server-only block below.
          "--flannel-conf=${flannelConf}"
        ]
        # ⚠️ **Server-only, and this is not a compromise — do not "fix" it by
        # moving it up into the all-nodes block.** k3s documents the Flannel
        # *cluster* options (backend, ipv6-masq, external-ip) as settable "only
        # on server nodes", identical across every server, and
        # `--flannel-ipv6-masq` is absent from `k3s agent --help` altogether —
        # verified on winkel-pi at v1.35.6+k3s1. Agents inherit the setting
        # from the servers, so winkel-pi's pods are masqueraded without the
        # flag ever being passed to them. Passing it there stops k3s outright,
        # because an unrecognised flag makes k3s refuse to start rather than
        # warn, and winkel-pi is the host where a failed rebuild has twice cost
        # a recovery.
        ++ lib.optionals (dual && isServer) [
          # Required, not optional: the pod CIDR is a ULA, so without
          # masquerading pods egress to the v6 internet using an address no
          # return path exists for. Replies are dropped upstream and the
          # failure looks like a dead destination rather than a NAT gap.
          "--flannel-ipv6-masq"
        ]
        ++ lib.optionals isServer [
          "--disable=servicelb" # MetalLB owns LoadBalancer (D5)
          "--disable=traefik" # Traefik is Pulumi-managed (D7)
          "--disable=local-storage" # storage is Phase 8's subject
          "--write-kubeconfig-mode=644"
          "--tls-san=${config.hostSpec.hostName}"
          "--tls-san=${self.overlayIPv4}"

          # ⚠️ These four sat inside the `lanInterface != null` guard below
          # until 2026-08-12, which meant **ionos — the cluster-init server —
          # received none of them**. It has no LAN interface, so the guard was
          # false on the one node whose flags bootstrap the cluster.
          #
          # It was invisible because the CIDRs happen to equal k3s's own
          # defaults, so only the D4 etcd tuning was actually missing. The
          # cluster CIDRs are a property of *the cluster*, not of whether a
          # given server also answers on its LAN, and the etcd tuning is about
          # the WAN paths between servers — which is exactly what ionos is at
          # the far end of. Nothing here has anything to do with lanInterface.
          "--cluster-cidr=${
            if dual
            then "${cluster.podCidrV4},${cluster.podCidrV6}"
            else cluster.podCidrV4
          }"
          "--service-cidr=${
            if dual
            then "${cluster.serviceCidrV4},${cluster.serviceCidrV6}"
            else cluster.serviceCidrV4
          }"

          # D4, from measurement rather than folklore: Phase 2 sampled p99
          # 6.8 ms direct and 23–25 ms relayed over 347 samples per direction.
          # 500/5000 sits 73× and 735× above that p99. Defaults (100/1000)
          # cause spurious leader elections across two consumer uplinks.
          "--etcd-arg=heartbeat-interval=500"
          "--etcd-arg=election-timeout=5000"
        ]
        ++ lib.optionals (isServer && dual) [
          # Same reasoning as the v4 SAN above: without it, anything reaching
          # the API over the node's overlay v6 address fails certificate
          # validation rather than failing to connect, which reads as a broken
          # cluster rather than a missing name.
          "--tls-san=${self.overlayIPv6}"

          # k3s documents this as needing to track the cluster-cidr mask but
          # gives no flag spelling, so it goes through the controller-manager
          # passthrough. /56 pod CIDR split into /64s per node — 256 subnets
          # against four nodes, matching the v4 side's generosity.
          "--kube-controller-manager-arg=node-cidr-mask-size-ipv6=64"
        ]
        ++ lib.optionals (isServer && cfg.lanInterface != null && self.lanIPv4 != null) [
          # Required for in-site access. Without it kubectl reaches 6443 on the
          # LAN and then fails validation — k3s issues the serving cert for the
          # node names and overlay addresses only, so the LAN address is absent
          # and the error looks like a certificate problem rather than a
          # missing SAN. Verified: the live cert's SANs are 100.64.0.1/.2/.5,
          # 10.43.0.1, 127.0.0.1 and the node names, with no LAN address.
          "--tls-san=${self.lanIPv4}"
        ]
        ++ lib.optionals cfg.clusterInit ["--cluster-init"]
        ++ cfg.extraFlags
      ));
    };
  };
}
