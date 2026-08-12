# Global Network Configuration
#
# `networkConfig.sites` / `.hosts` is the model, and since Phase 6 it is the
# only one — the flat single-site options this repo was built on are gone,
# along with the microVMs and maxdata's use of them. What remains outside it is
# `domain` and the `legacy.*` VIPs, both of which are named for what they are.
#
# See docs/multi-site-migration.md.
{
  lib,
  config,
  ...
}: let
  siteModule = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "Human-readable site name";
      };
      router = lib.mkOption {
        type = lib.types.str;
        description = "Router model/product at this site";
      };
      subnet = lib.mkOption {
        type = lib.types.str;
        description = "LAN subnet in CIDR form";
      };
      gateway = lib.mkOption {
        type = lib.types.str;
        description = "Default gateway (the router)";
      };
      dnsServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          Resolvers handed to hosts at this site, in order: the site's AdGuard
          first, the router second (Phase 4). This deliberately mirrors what
          the router hands out over DHCP, so a statically-configured host and
          a DHCP client see the same resolvers in the same order.

          No public resolver belongs in this list. Falling through to one
          bypasses ad-blocking and split-horizon together, which fails
          intermittently rather than cleanly.
        '';
      };
      adguard = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          LAN address of this site's native AdGuard instance. Null until
          Phase 4 deploys it.
        '';
      };
      ulaPrefix = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Stable ULA /64 for this site (RFC 4193), advertised by the router
          alongside the delegated global prefix.

          It exists for exactly one reason: to give the site's resolver an
          IPv6 address that does not move. D2 forbids depending on the
          Deutsche Glasfaser prefix — it changes unannounced — so a resolver
          addressed inside it would silently stop being reachable at the
          address the router advertises. A ULA is generated once and is ours
          forever.

          All from one estate /48, `fd06:f10a:ebec::/48`, chosen randomly per
          RFC 4193 §3.2.2. Deliberately clear of two ranges already in use:
          Tailscale's `fd7a:115c:a1e0::/48` and the legacy
          `fda8:a1db:5685::/48` that ionos's wg0 still carries until Phase 13.
        '';
      };
      adguardIPv6 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          This site's AdGuard on its ULA, and the address the router hands out
          over RDNSS/DHCPv6.

          ⚠️ Needed because clients *prefer* an RA-advertised IPv6 resolver
          over the DHCPv4 one. Setting only the DHCPv4 DNS server leaves
          `nameserver[0]` pointing at the router, so ad-blocking and
          split-horizon both appear not to work — measured on the Brink Mac,
          2026-08-06, where nameserver[0] was the UDM SE's own GUA.

          The host part mirrors the IPv4 last octet, so `…:1::2` is
          brink-server at `192.168.1.2` and `…:178::3` is winkel-pi at
          `192.168.178.3`.
        '';
      };
      metallbPool = lib.mkOption {
        type = lib.types.str;
        description = ''
          MetalLB L2 pool for this site, advertised only by nodes at this site.
          Must sit outside the router's DHCP range.
        '';
      };
      ingressVIP = lib.mkOption {
        type = lib.types.str;
        description = "Site-local Traefik LoadBalancer address (first of metallbPool)";
      };
      dhcpRange = lib.mkOption {
        type = lib.types.str;
        description = ''
          Documentation only — DHCP is served by the router, never by this
          fleet. Recorded so the MetalLB pool can be kept clear of it.
        '';
      };
    };
  };

  hostModule = lib.types.submodule {
    options = {
      site = lib.mkOption {
        type = lib.types.enum ["brink" "winkel" "public"];
        description = "Which site this host is physically at";
      };
      lanIPv4 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static LAN address at its site; null for hosts with no LAN";
      };
      publicIPv4 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Fixed public IPv4, if any";
      };
      publicIPv6 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Fixed public IPv6, if any";
      };
      overlayIPv4 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Mesh-overlay address. Assigned by the control server in Phase 3 and
          recorded back here — it becomes the k3s --node-ip (D3).
        '';
      };
      overlayIPv6 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Mesh-overlay IPv6 address, the v6 half of `--node-ip` under D17.

          ⚠️ **Must be read off the live tailnet, never guessed.** Headscale
          has been allocating these from `fd7a:115c:a1e0::/48` since Phase 3
          purely by nixpkgs default — nothing in this repo asked for it and
          nothing recorded the result. Allocation is `sequential`, so the
          values *look* predictable from the v4 assignments, but the mapping is
          an implementation detail of the control server and a wrong node-ip is
          D3's failure mode: the node comes up on an address the rest of the
          cluster cannot reach.

          Get them with `headscale nodes list` on ionos, or `tailscale ip -6`
          on each node, and paste them in.

          Choosing the overlay rather than a site prefix is what keeps D2
          intact: these addresses are ours and stable, whereas the Deutsche
          Glasfaser /56 at each site changes unannounced. It also means maxdata
          needing no LAN ULA of its own stays irrelevant to the cluster.
        '';
      };
      k3sRole = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum ["server" "agent"]);
        default = null;
        description = "Target k3s role from Phase 7; null means not a cluster member";
      };
      subnetRouter = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether this host advertises its site's whole subnet onto the overlay,
          making unmodified LAN clients reachable from the other site (Phase 3).

          Exactly one host per site should set this. The router's static route
          for the *remote* subnet points at its own site's subnet router, never
          at the remote one — a router can only hand a packet to an address it
          can already reach.
        '';
      };
    };
  };
in {
  options.networkConfig = {
    # ---------------------------------------------------------------------
    # Multi-site model
    # ---------------------------------------------------------------------

    sites = lib.mkOption {
      type = lib.types.attrsOf siteModule;
      description = "Physical sites";
      default = {
        brink = {
          description = "Brinkstraße, Borken — own apartment";
          router = "UDM SE";
          subnet = "192.168.1.0/24";
          gateway = "192.168.1.1";
          # AdGuard first, the router second — the same pair the UDM SE hands
          # out over DHCP, so a host and a DHCP client resolve identically.
          #
          # 1.1.1.1 is deliberately gone. A public resolver in this list is not
          # a safety net, it is a hole: a client that falls through to it
          # bypasses both ad-blocking *and* split-horizon, so *.mvissing.de
          # would silently resolve to the dead public ingress instead of the
          # site VIP — and intermittently, depending on which server answered.
          # The router is the correct fallback because it is the one resolver
          # that is up whenever the LAN is.
          #
          # ⚠️ This list means *failover* to systemd-resolved and *load
          # balancing* to CoreDNS, and that difference cost an outage
          # (Phase 10, 2026-08-08). resolved elects one server and sticks —
          # so the router is reached only when AdGuard is genuinely down, which
          # is the leaky-but-bounded behaviour these comments assume. CoreDNS's
          # `forward` plugin defaults to `policy random`, so k3s — which
          # inherits this list via `forward . /etc/resolv.conf` — used it as a
          # coin flip on every cache miss, and roughly half of all in-cluster
          # `*.mvissing.de` lookups resolved to the public edge. That edge is
          # default-closed, so it answers with a self-signed certificate and
          # every server-side HTTPS call from a pod failed verification.
          #
          # The fix belongs in the cluster, not here: `infrastructure/coredns.ts`
          # in `homelab-k8s` pins `mvissing.de` to the two site AdGuards with
          # `policy sequential`, which is CoreDNS's actual failover. The router
          # stays in this list because for a *host* it was never the problem —
          # and brink-server is the only node at Brink, so removing its last
          # fallback would cost more than it buys.
          #
          # ⚠️ Anything else that consumes this list should be checked for the
          # same assumption before it is trusted.
          dnsServers = ["192.168.1.2" "192.168.1.1"];
          # brink-server's own LAN address. modules/system/site-dns.nix
          # asserts this equals hosts.brink-server.lanIPv4, so the UDM SE's
          # DHCP setting and the address AdGuard binds cannot drift apart.
          adguard = "192.168.1.2";
          ulaPrefix = "fd06:f10a:ebec:1::/64";
          adguardIPv6 = "fd06:f10a:ebec:1::2";
          metallbPool = "192.168.1.240-192.168.1.250";
          ingressVIP = "192.168.1.240";
          dhcpRange = "192.168.1.6-192.168.1.199"; # after shrinking from auto (.6-.254)
        };
        winkel = {
          description = "Nina-Winkel-Straße, Borken — parents' house";
          router = "FritzBox";
          subnet = "192.168.178.0/24";
          gateway = "192.168.178.1";
          # AdGuard first, FritzBox second — see the note on brink above for
          # why no public resolver appears here.
          dnsServers = ["192.168.178.3" "192.168.178.1"];
          # winkel-pi's own LAN address; see the note on brink above.
          #
          # ⚠️ Not to be confused with 192.168.178.14, the *in-cluster*
          # AdGuard on a MetalLB address that Winkel clients use today. That
          # one keeps running until Phase 8 deletes it — Phase 4 stands a
          # second resolver up beside it rather than replacing it in place.
          adguard = "192.168.178.3";
          ulaPrefix = "fd06:f10a:ebec:178::/64";
          adguardIPv6 = "fd06:f10a:ebec:178::3";
          metallbPool = "192.168.178.240-192.168.178.250";
          ingressVIP = "192.168.178.240";
          dhcpRange = "192.168.178.20-192.168.178.200"; # as-is, no change needed
        };
      };
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf hostModule;
      description = "Cluster and infrastructure hosts, and where they live";
      default = {
        brink-server = {
          site = "brink";
          lanIPv4 = "192.168.1.2";
          overlayIPv4 = "100.64.0.2";
          # Read off the live tailnet with `tailscale ip -6`, 2026-08-12.
          overlayIPv6 = "fd7a:115c:a1e0::2";
          k3sRole = "server";
          subnetRouter = true; # Brink's only always-on host
        };
        maxdata = {
          site = "winkel";
          lanIPv4 = "192.168.178.2";
          overlayIPv4 = "100.64.0.5";
          # Read off the live tailnet with `tailscale ip -6`, 2026-08-12.
          # ⚠️ `.5`, not `.4` — the iPhone holds `100.64.0.4`. The sequence is
          # enrolment order, which is exactly why these are read and not derived.
          overlayIPv6 = "fd7a:115c:a1e0::5";
          k3sRole = "server";
          # Deliberately not a subnet router (3.1): the pi is, so a rebuild of
          # maxdata cannot take Winkel's routing down with it.
        };
        winkel-pi = {
          site = "winkel";
          lanIPv4 = "192.168.178.3";
          overlayIPv4 = "100.64.0.3";
          # Read off the live tailnet with `tailscale ip -6`, 2026-08-12.
          overlayIPv6 = "fd7a:115c:a1e0::3";
          k3sRole = "agent";
          subnetRouter = true; # D10 — the unattended-site anchor
        };
        ionos = {
          site = "public";
          publicIPv4 = "212.132.82.102";
          publicIPv6 = "2a02:2479:5c:a00::1";
          overlayIPv4 = "100.64.0.1";
          # Read off the live tailnet with `tailscale ip -6`, 2026-08-12.
          overlayIPv6 = "fd7a:115c:a1e0::1";
          k3sRole = "server";
        };
      };
    };

    # ---------------------------------------------------------------------
    # Mesh overlay (Phase 3) — Headscale control server + Tailscale clients
    # ---------------------------------------------------------------------

    overlay = {
      controlServerHost = lib.mkOption {
        type = lib.types.str;
        default = "headscale.mvissing.de";
        description = ''
          Public hostname of the Headscale control server on ionos. Needs an
          A/AAAA record pointing at ionos, and it must resolve publicly because
          Let's Encrypt validates it over HTTP-01.
        '';
      };
      controlServerUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://${config.networkConfig.overlay.controlServerHost}";
        readOnly = true;
        description = ''
          What clients pass to `--login-server`. **HTTPS on 443, never plain
          HTTP on an alternate port** — Phase 2 showed a client's fallback
          heuristic escalates to port 443 after any control interruption and
          then wedges permanently (overlay-evaluation §2.1).
        '';
      };
      magicDnsBaseDomain = lib.mkOption {
        type = lib.types.str;
        default = "mesh.mvissing.de";
        description = ''
          MagicDNS suffix for node names. Headscale requires this to differ
          from the server_url hostname, so it cannot be `mvissing.de` itself.
        '';
      };
      roamingResolver = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = config.networkConfig.hosts.ionos.overlayIPv4;
        description = ''
          Overlay address of the resolver Headscale pushes to every tailnet
          client (D15). Null disables the push and leaves clients on whatever
          their local network hands them.

          This is the roaming counterpart to `sites.<site>.adguard`, and it has
          the same drift hazard, so it is checked the same way:
          `modules/system/roaming-dns.nix` asserts this equals the overlay
          address of the host actually running that resolver, because the value
          is *published* by Headscale (`hosts/nixos/ionos/overlay-server.nix`)
          and *bound* by AdGuard, in two files that never reference each other.

          ⚠️ **Why a third resolver rather than pointing the tailnet at a site.**
          Tailnet DNS is global, but the two site resolvers answer
          `*.mvissing.de` *differently on purpose* — brink rewrites to
          192.168.1.240, winkel to 192.168.178.240. Naming either one here
          gives every roaming *and* on-site client the wrong site's ingress
          VIP. The roaming view has no rewrites at all, which is correct: a
          client on neither LAN should get the public address, which is what
          public DNS already returns.

          ⚠️ Safe to push fleet-wide only because every NixOS host passes
          `--accept-dns=false` (`modules/system/overlay-client.nix:78`), so no
          server follows it. Drop that flag on a host and it starts resolving
          through ionos, losing split-horizon and gaining a dependency on the
          VPS for all name resolution.
        '';
      };
      prefixV4 = lib.mkOption {
        type = lib.types.str;
        default = "100.64.0.0/10";
        description = "Overlay IPv4 pool. Must sit inside Tailscale's 100.64.0.0/10.";
      };
      prefixV6 = lib.mkOption {
        type = lib.types.str;
        default = "fd7a:115c:a1e0::/48";
        description = ''
          Overlay IPv6 pool.

          ⚠️ **This is not new behaviour — it is behaviour that was never
          written down.** Headscale has allocated from this range since Phase 3
          because it is the nixpkgs module's default and
          `hosts/nixos/ionos/overlay-server.nix` set only `prefixes.v4`. Every
          node has had an `fd7a:` address all along; nothing referenced it, so
          the estate ULA in `sites.<x>.ulaPrefix` was deliberately chosen clear
          of this range without the range itself ever being declared.

          Stated explicitly now that D17 makes it load-bearing: it is where
          `hosts.<h>.overlayIPv6` comes from, and a control-server default that
          silently moved would take the cluster's node IPs with it.
        '';
      };
      derpRegionId = lib.mkOption {
        type = lib.types.int;
        default = 999;
        description = ''
          Region id for ionos's embedded DERP. Kept in the private range so it
          never collides with Tailscale's public regions. Relay stays inside
          the estate rather than transiting Tailscale's infrastructure.
        '';
      };
      derpStunPort = lib.mkOption {
        type = lib.types.port;
        default = 3478;
        description = ''
          STUN port for NAT traversal, UDP. ⚠️ Must be opened in the **IONOS
          Cloud firewall**, which is default-deny and invisible from inside the
          VPS — blocked packets never reach `ens6`, so tcpdump shows nothing.
        '';
      };
      mtu = lib.mkOption {
        type = lib.types.int;
        default = 1380;
        description = ''
          Overlay MTU, imposed on `tailscale0` by
          `modules/system/overlay-client.nix` and consumed by
          `modules/system/k3s-cluster.nix` to derive the flannel MTU. A wrong
          value blackholes large payloads while ping still succeeds (D3).

          ⚠️ **Until 2026-08-12 this option had no consumers at all.** It
          recorded Phase 2's measurement while the live 1230 flannel MTU was
          produced by interface inheritance — flannel reading `tailscale0`'s
          own 1280. Changing the number here changed nothing. It is now
          enforced at both ends, which also means changing it now genuinely
          moves the cluster's MTU.

          The old default of 1280 was Tailscale's `safeTUNMTU`, not a
          measurement of the path. It is also exactly the IPv6 minimum link
          MTU, which is what made it unusable for dual-stack — see
          `cluster.dualStack` for the arithmetic.

          **1380 is measured (14.1, 2026-08-12), and the number is chosen by
          the *fallback* path rather than the fast one.** All 12 directed pairs
          carried 1400 at 0% loss, with a byte-exact 20 MB transfer on each of
          the three paths the cluster can actually take. The binding constraint
          is not the steady-state IPv6 path but the IPv4 one through Brink's
          DS-Lite CGNAT, which appears the moment native IPv6 is unavailable:

            1400 + 32 WG + 8 UDP + 20 IPv4        = 1460
                 + 40 DS-Lite v4-in-v6 to the AFTR = 1500  ← the physical MTU exactly

          That passed, with **zero bytes spare**. 1380 keeps 20 bytes of margin
          on *both* underlay families (1460 over IPv4+DS-Lite, 1440 over IPv6)
          and still puts flannel at 1310, clear of the 1280 IPv6 floor. ⚠️ Do
          not raise this to 1400 for the extra headroom it appears to give:
          that headroom exists only on the path that works, and the path that
          matters is the one that appears during an incident.
        '';
      };
    };

    # ---------------------------------------------------------------------
    # Cluster address plan (D1, reversed by D17)
    # ---------------------------------------------------------------------
    #
    # These were inline literals in modules/system/k3s-cluster.nix until D17.
    # They are addresses, so they belong here — and under dual-stack there are
    # four of them rather than two, with a live consistency requirement between
    # the k3s flags and the flannel config that only holds if both derive from
    # one source.

    cluster = {
      dualStack = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether the cluster runs dual-stack IPv4+IPv6 (D17, reversing D1).

          ⚠️ **This cannot be flipped on a running cluster.** k3s is explicit:
          dual-stack must be configured when the cluster is first created and
          cannot be enabled on an existing IPv4-only cluster. Flipping this is
          therefore a *rebuild instruction*, not a switch — every node must be
          reset and the cluster rebuilt from `--cluster-init`.

          ⚠️ **Requires `overlay.mtu` ≥ 1350, and that is arithmetic rather
          than caution.** Flannel sets both VXLAN devices to
          `extIface.MTU − 50`, a constant that is blind to the IP version of
          the outer header (`vxlan/device.go`; `encapOverhead = 50`). The Linux
          kernel refuses IPv6 on any device below `IPV6_MIN_MTU` = 1280
          (`addrconf.c`, `-EINVAL` on add and `addrconf_ifdown()` on
          `NETDEV_CHANGEMTU`). So `flannel-v6.1` needs `mtu − 50 ≥ 1280`.

          The real overhead with `fd7a:` VTEPs is 70, not 50 — a 40-byte IPv6
          outer header rather than 20 — so flannel over-claims by 20 bytes at
          *every* underlay MTU. That is why `k3s-cluster.nix` pins the flannel
          MTU explicitly at `mtu − 70` instead of letting it inherit.

          The assertions in `k3s-cluster.nix` enforce both of these.
        '';
      };
      podCidrV4 = lib.mkOption {
        type = lib.types.str;
        default = "10.42.0.0/16";
        description = "Pod CIDR, IPv4. k3s's own default, kept deliberately.";
      };
      podCidrV6 = lib.mkOption {
        type = lib.types.str;
        default = "fd06:f10a:ebec:4200::/56";
        description = ''
          Pod CIDR, IPv6. Carved from the estate ULA `fd06:f10a:ebec::/48`
          rather than resurrecting D1's `fd01::/48`, so the whole estate stays
          inside one randomly-generated /48 and the `:42:`/`:43:` subnet ids
          echo the v4 `10.42`/`10.43` they sit beside.

          ⚠️⚠️ **This was `fd06:f10a:ebec:42::/56` and that value was broken in
          a way nothing here caught — fixed 2026-08-12, mid-rebuild, after the
          first node had already allocated from it.** A /56 mask ends *inside*
          the fourth hextet, so `…:0042::/56` is not the "42 block": it
          normalises to **`fd06:f10a:ebec::/56`**, spanning `…:0000::` to
          `…:00ff::`. The `:42:` label is in the host part and is silently
          discarded. Consequences, both real and both measured with
          `ipaddress`:

            - it **contained the service CIDR** `…:43::/112`, since 0x0043 is
              inside 0x0000–0x00ff; and
            - it **contained Brink's site ULA** `…:1::/64`. Node CIDRs are
              handed out sequentially from the base, so the *second* node to
              join takes `fd06:f10a:ebec:1::/64` — byte-for-byte
              brink-server's own LAN prefix. ionos took `…:0000::/64` and the
              collision was one join away.

          `…:4200::/56` is /56-aligned, so the visible `42` survives the mask,
          and it overlaps neither site ULA nor the service CIDR. ⚠️ **Check
          alignment with a tool, not by reading the literal** — a v6 prefix
          that "looks like" it names a subnet may not, and nothing in the k3s
          flags, the flannel config or the assertions rejects an unaligned one.

          /56 with the default `node-cidr-mask-size-ipv6` of 64 gives 256 node
          subnets, against four nodes.

          ULA rather than the site GUAs because D2 forbids depending on the
          Deutsche Glasfaser prefix. The cost is that pod egress to the v6
          internet needs `--flannel-ipv6-masq`, which `k3s-cluster.nix` sets.
        '';
      };
      serviceCidrV4 = lib.mkOption {
        type = lib.types.str;
        default = "10.43.0.0/16";
        description = "Service CIDR, IPv4. k3s's own default, kept deliberately.";
      };
      serviceCidrV6 = lib.mkOption {
        type = lib.types.str;
        default = "fd06:f10a:ebec:43::/112";
        description = ''
          Service CIDR, IPv6. ⚠️ /112 is the **largest mask k3s supports** for
          an IPv6 service CIDR — a wider one is rejected rather than clamped.
        '';
      };
    };

    # ---------------------------------------------------------------------
    # Single-site leftovers
    #
    # ✅ Phase 6 removed the deprecated block that lived here: dns.primary,
    # dns.servers, gateway, subnet, staticIPs, staticIPv6s and ipv6Gateway.
    # Their only consumers were the deleted modules/system/k3s-node.nix (the
    # three microVMs) and hosts/nixos/maxdata/networking.nix — maxdata now
    # reads sites.winkel like every other host, ending the
    # last case of a host at either site not using its own site resolver.
    #
    # `domain` is not part of that block and stays: it is the local DNS suffix,
    # consumed by modules/system/base.nix, and has no site dimension.
    # ---------------------------------------------------------------------

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local";
      description = "Local domain name";
    };

    # ---------------------------------------------------------------------
    # Undeclared constants promoted out of hardcoded literals (Phase 0.3)
    # ---------------------------------------------------------------------

    legacy = {
      ingressVIP = lib.mkOption {
        type = lib.types.str;
        default = "192.168.178.10";
        description = ''
          The MetalLB address Traefik currently holds, hardcoded into six
          iptables DNAT rules on ionos and declared nowhere until now. It was
          never reserved — MetalLB assigned it first-come from the .10-.20 pool
          and a rebuild would not reproduce it. Replaced by
          sites.<x>.ingressVIP once D7 removes the DNAT path in Phase 9.
        '';
      };
      ingressVIPv6 = lib.mkOption {
        type = lib.types.str;
        default = "fda8:a1db:5685::10";
        description = "IPv6 counterpart of legacy.ingressVIP. Removed with D1.";
      };
    };

    # ---------------------------------------------------------------------
    # Cluster service addresses this fleet has to know about
    # ---------------------------------------------------------------------

    lokiVIP = lib.mkOption {
      type = lib.types.str;
      default = "192.168.178.241";
      description = ''
        In-cluster Loki LoadBalancer, consumed by maxdata's Alloy
        (hosts/nixos/maxdata/monitoring.nix). Sits in sites.winkel.metallbPool.

        ⚠️ Moved out of `legacy` in Phase 8 and repinned .11 → .241 with the
        pool. It is no longer an undeclared literal: homelab-k8s pins it
        explicitly in infrastructure/sites.ts, and MetalLB's winkel-pool has
        autoAssign disabled, so the address is reserved rather than won by
        allocation order.

        ⚠️ This is a two-repo constant with no link between the copies. If the
        Pulumi pin and this value disagree, Alloy ships maxdata's journal to an
        address nothing answers on — and **nothing reports an error**. Loki
        just never hears from maxdata. Verify after any change by querying
        Loki for the maxdata job, not by checking that Alloy is running.
      '';
    };
  };
}
