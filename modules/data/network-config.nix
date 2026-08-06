# Global Network Configuration
#
# Two layers live here during the multi-site migration:
#
#   networkConfig.sites / .hosts   — the multi-site model. Source of truth from
#                                    Phase 3 onwards.
#   everything else                — the single-site model this repo was built
#                                    on. Still consumed by the microVMs and
#                                    maxdata; removed in Phase 6.
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
          Resolvers handed to hosts at this site, in order. Until Phase 4 this
          is the router plus a public fallback; afterwards the site's AdGuard
          comes first.
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
          dnsServers = ["192.168.1.1" "1.1.1.1"];
          # brink-server's own LAN address. modules/system/site-dns.nix
          # asserts this equals hosts.brink-server.lanIPv4, so the UDM SE's
          # DHCP setting and the address AdGuard binds cannot drift apart.
          adguard = "192.168.1.2";
          metallbPool = "192.168.1.240-192.168.1.250";
          ingressVIP = "192.168.1.240";
          dhcpRange = "192.168.1.6-192.168.1.199"; # after shrinking from auto (.6-.254)
        };
        winkel = {
          description = "Nina-Winkel-Straße, Borken — parents' house";
          router = "FritzBox";
          subnet = "192.168.178.0/24";
          gateway = "192.168.178.1";
          dnsServers = ["192.168.178.1" "1.1.1.1"];
          # winkel-pi's own LAN address; see the note on brink above.
          #
          # ⚠️ Not to be confused with 192.168.178.14, the *in-cluster*
          # AdGuard on a MetalLB address that Winkel clients use today. That
          # one keeps running until Phase 8 deletes it — Phase 4 stands a
          # second resolver up beside it rather than replacing it in place.
          adguard = "192.168.178.3";
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
          k3sRole = "server";
          subnetRouter = true; # Brink's only always-on host
        };
        maxdata = {
          site = "winkel";
          lanIPv4 = "192.168.178.2";
          # overlayIPv4 still null: maxdata has not joined, because its sops
          # wiring is Phase 6.1 and it cannot decrypt the auth key until then.
          k3sRole = "server";
          # Deliberately not a subnet router (3.1): the pi is, so a rebuild of
          # maxdata cannot take Winkel's routing down with it.
        };
        winkel-pi = {
          site = "winkel";
          lanIPv4 = "192.168.178.3";
          overlayIPv4 = "100.64.0.3";
          k3sRole = "agent";
          subnetRouter = true; # D10 — the unattended-site anchor
        };
        ionos = {
          site = "public";
          publicIPv4 = "212.132.82.102";
          publicIPv6 = "2a02:2479:5c:a00::1";
          overlayIPv4 = "100.64.0.1";
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
      prefixV4 = lib.mkOption {
        type = lib.types.str;
        default = "100.64.0.0/10";
        description = "Overlay IPv4 pool. Must sit inside Tailscale's 100.64.0.0/10.";
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
        default = 1280;
        description = ''
          Measured overlay MTU (Phase 2 → D3). Flannel gets this minus 50 for
          VXLAN overhead in Phase 7. A wrong value blackholes large payloads
          while ping still succeeds.
        '';
      };
    };

    # ---------------------------------------------------------------------
    # Legacy single-site model — removed in Phase 6
    #
    # Consumed by modules/system/k3s-node.nix (the microVMs) and
    # hosts/nixos/maxdata/networking.nix. Values describe the winkel site only.
    # ---------------------------------------------------------------------

    dns = {
      primary = lib.mkOption {
        type = lib.types.str;
        default = "192.168.178.1";
        description = "DEPRECATED. Primary DNS server (FritzBox). Use sites.<x>.dnsServers.";
      };
      servers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["192.168.178.1" "1.1.1.1"];
        description = "DEPRECATED. Use sites.<x>.dnsServers.";
      };
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      default = "192.168.178.1";
      description = "DEPRECATED. Use sites.<x>.gateway.";
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      default = "192.168.178.0/24";
      description = "DEPRECATED. Use sites.<x>.subnet.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local";
      description = "Local domain name";
    };

    staticIPs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        maxdata = "192.168.178.2";
        k3s-node1 = "192.168.178.5";
        k3s-node2 = "192.168.178.6";
        k3s-node3 = "192.168.178.7";
        ionos = "192.168.178.201"; # Via WireGuard
      };
      description = "DEPRECATED. Use hosts.<x>.lanIPv4 / .overlayIPv4.";
    };

    staticIPv6s = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        # Private ULA addresses - NOT exposed to internet
        # Only accessible via local network or WireGuard tunnel
        maxdata = "fda8:a1db:5685::2";
        k3s-node1 = "fda8:a1db:5685::5";
        k3s-node2 = "fda8:a1db:5685::6";
        k3s-node3 = "fda8:a1db:5685::7";
        ionos = "fda8:a1db:5685::201"; # Via WireGuard
      };
      description = ''
        DEPRECATED. Cluster dual-stack is dropped by D1; the overlay replaces
        the ULA. Note maxdata never actually applies its entry — only the
        microVMs consume this.
      '';
    };

    ipv6Gateway = lib.mkOption {
      type = lib.types.str;
      default = "fda8:a1db:5685::1";
      description = "DEPRECATED. IPv6 gateway (local). Nothing references this.";
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
      lokiVIP = lib.mkOption {
        type = lib.types.str;
        default = "192.168.178.11";
        description = ''
          In-cluster Loki LoadBalancer, hardcoded in maxdata's Alloy config
          (hosts/nixos/maxdata/monitoring.nix:67). Moves with the pool in
          Phase 8.
        '';
      };
    };
  };
}
