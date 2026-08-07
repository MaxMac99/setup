# Site DNS resolver — AdGuard Home, natively on NixOS. Phase 4.
#
# One instance per site: brink-server at Brink, winkel-pi at Winkel. Each
# router hands out its own site's instance as primary resolver and itself as
# secondary, so a dead AdGuard makes ad-blocking leaky rather than taking the
# site offline.
#
# This is deliberately *not* in the cluster (layering rule): DNS has to survive
# a cluster rebuild, and Phases 7-10 rebuild the cluster from nothing.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.siteDns;
  net = config.networkConfig;
  self = net.hosts.${config.hostSpec.hostName} or null;
  site =
    if self == null || self.site == "public"
    then null
    else net.sites.${self.site};

  # Tailscale's fixed MagicDNS resolver address. It answers on the TUN even
  # though every client runs --accept-dns=false — verified on winkel-pi
  # 2026-08-06, where `brink-server.mesh.mvissing.de` resolved to 100.64.0.2
  # against this address. --accept-dns=false only stops tailscaled rewriting
  # /etc/resolv.conf; it does not stop it answering. That is what lets node
  # names stay automatic instead of being duplicated into this file.
  magicDnsResolver = "100.100.100.100";
in {
  options.siteDns = {
    enable = lib.mkEnableOption "AdGuard Home as this site's DNS resolver";

    uiPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = ''
        Port for the admin web interface, bound to this host's LAN address
        only (never 0.0.0.0).

        ⚠️ Authentication is *not* declared here. The in-cluster instance ran
        with `users: []` because Authentik fronted it; natively nothing does.
        `mutableSettings` is true and `users` is deliberately left undeclared,
        so a password set once in the UI survives every later rebuild — see
        the note on merge semantics below. Until that is done the UI is open
        to anyone on the LAN or the overlay.
      '';
    };

    splitHorizonDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "mvissing.de";
      description = ''
        Domain whose subdomains resolve to this site's own ingress VIP instead
        of to the public address (D9). Set to null to disable split-horizon
        entirely.

        The apex is rewritten too, and needs its own entry because AdGuard's
        `*.example.org` wildcard does not match `example.org` itself.

        ⚠️ **This reverses a Phase 4 decision, and the reversal is the point.**
        That decision excluded the apex on the grounds that it "is the one name
        a real public website would later live at". No such website exists;
        what actually lives there is **Homepage**, the dashboard
        (`apps/homepage.ts` in `homelab-k8s`, host `mvissing.de`). The
        exclusion therefore did not reserve the apex for a hypothetical, it
        broke the estate's most prominent name for every client at both sites:
        `mvissing.de` resolved to ionos, where the default-closed public edge
        answers with `CN=TRAEFIK DEFAULT CERT` and 404. Measured from a Brink
        client 2026-08-07 — `dig mvissing.de` → `212.132.82.102` while
        `grafana.mvissing.de` → `192.168.1.240`, and forcing the apex to the
        site VIP gave a clean 302 with a valid certificate. The internal
        Traefik had been serving it correctly the whole time; only DNS was
        wrong.

        ⚠️ **Untested edge, and the one to check before ever adding mail to
        this domain.** The apex has no MX, TXT or CAA records — re-verified
        against 1.1.1.1 on 2026-08-07, unchanged since the Phase 4 check — so
        nothing can be measured about how AdGuard treats non-address queries
        for a name that carries an address rewrite. AdGuard rewrites are
        documented as A/AAAA/CNAME, but a rewrite is capable of turning other
        types into NODATA, and that failure would be silent: mail would simply
        stop being delivered with the DNS config reading as correct. If SPF,
        DMARC or an MX is ever added at the apex, query those types against a
        site resolver *and* against 1.1.1.1 and compare, before trusting it.
        Adding a public website has the same shape — internal clients would
        keep getting the dashboard, and this entry is the one line to remove.
      '';
    };

    passthroughNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # ⚠️ **The load-bearing exclusion.** Without this the split-horizon
        # wildcard swallows the Headscale control server and *both* sites lose
        # the overlay — including the hosts running this very resolver.
        net.overlay.controlServerHost

        # MagicDNS. These have to reach the domain-specific upstream below
        # rather than be rewritten, because rewrites are applied before
        # upstream selection. Note the public zone has a wildcard that answers
        # these with ionos's address today, which is simply wrong; passing
        # them through to 100.100.100.100 is a fix, not just an exemption.
        net.overlay.magicDnsBaseDomain
        "*.${net.overlay.magicDnsBaseDomain}"
      ];
      description = ''
        Names under `splitHorizonDomain` that must keep resolving normally.

        Implemented with AdGuard's documented pass-through rewrite: an `answer`
        of `A` or `AAAA` means "keep the upstream's records of that type"
        rather than substituting an address. A more specific rewrite wins over
        a less specific one, so these beat the wildcard.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = self != null && site != null;
        message = "siteDns: ${config.hostSpec.hostName} has no networkConfig.hosts entry at a real site; a resolver needs a site to serve.";
      }
      {
        assertion = self == null || self.lanIPv4 != null;
        message = "siteDns: ${config.hostSpec.hostName} has no lanIPv4; AdGuard binds a fixed LAN address, never a lease.";
      }
      {
        # The anti-drift check this module exists to make impossible to skip.
        # networkConfig.sites.<site>.adguard is what the *routers* are
        # configured from (their DHCP hands it out as primary resolver). If it
        # ever disagreed with the address AdGuard actually binds, the whole
        # site would be pointed at nothing, and the two facts live in
        # different systems where nothing would catch it.
        assertion = site == null || site.adguard == self.lanIPv4;
        message = "siteDns: networkConfig.sites.${self.site}.adguard is ${toString (site.adguard or null)} but ${config.hostSpec.hostName} binds ${toString self.lanIPv4}. The routers' DHCP is configured from the former and AdGuard listens on the latter — they must not drift.";
      }
    ];

    services.adguardhome = {
      enable = true;

      # Admin UI on the LAN address only. `openFirewall` is deliberately not
      # used: it opens *this* port and explicitly not port 53, which is the
      # one that matters, so it reads as protection it does not provide.
      host = self.lanIPv4;
      port = cfg.uiPort;

      # ⚠️ Merge semantics, because they decide what is declarative here.
      # With mutableSettings the module runs `yaml-merge <state> <declared>`:
      # a *recursive dict merge* where declared values win and **lists are
      # replaced wholesale**. So:
      #   - keys not named below (notably `users`) persist across rebuilds;
      #   - `filters`, `rewrites` and `upstream_dns` are authoritative here,
      #     and edits made to them in the UI are reverted on next restart.
      # That is the split we want: policy in git, credentials on the host.
      mutableSettings = true;

      settings = {
        dns = {
          # Bind the LAN address explicitly rather than 0.0.0.0. brink-server
          # runs systemd-resolved (implied by networking.useNetworkd), whose
          # stub already holds 127.0.0.53:53 and 127.0.0.54:53 — a wildcard
          # bind collides with it. winkel-pi has no resolved at all, so this
          # is also the one form that is correct on both hosts.
          #
          # 127.0.0.1 is free on both and lets the host query itself without
          # a round trip to its own LAN address.
          #
          # Not bound: the overlay address. AdGuard starts long before
          # tailscale0 has one, and binding an address that does not exist yet
          # means crash-looping until it does. Overlay peers reach this
          # resolver through the subnet router at its LAN address anyway.
          #
          # The site ULA is bound too, and it is not cosmetic: clients prefer
          # an RA-advertised IPv6 resolver over the DHCPv4 one, so without an
          # IPv6 listener the routers have nothing to advertise and Phase 4
          # never reaches a single client. Static address, so it is up before
          # this service starts.
          bind_hosts =
            [self.lanIPv4 "127.0.0.1"]
            ++ lib.optional (site.adguardIPv6 != null) site.adguardIPv6;
          port = 53;

          # Cloudflare DoH, matching what the in-cluster instance used
          # (apps/adguard.ts). The bootstrap entries are literal addresses, so
          # there is no chicken-and-egg: resolving the DoH hostname never
          # needs DNS.
          upstream_dns = [
            "https://1.1.1.1/dns-query"
            "https://1.0.0.1/dns-query"

            # Overlay node names, straight from tailscaled. dnsmasq-style
            # domain-specific upstream: only this suffix goes here, and if
            # tailscaled is down these names fail rather than falling back to
            # the public wildcard and answering with a wrong address.
            "[/${net.overlay.magicDnsBaseDomain}/]${magicDnsResolver}"
          ];
          bootstrap_dns = ["1.1.1.1" "1.0.0.1"];
          upstream_mode = "load_balance";

          # PTR for LAN clients goes to the site's router, which is the only
          # thing that knows its own DHCP leases. Without this AdGuard guesses
          # local resolvers from the OS, which on brink-server means
          # systemd-resolved pointing back at AdGuard.
          use_private_ptr_resolvers = true;
          local_ptr_upstreams = [site.gateway];

          # ⚠️ Disabled on purpose. The default is 20 queries/second, and
          # `ratelimit_subnet_len_ipv4` defaults to 24 — so the *entire /24*
          # shares one 20 qps bucket, not each client. On a site resolver that
          # is a self-inflicted outage waiting for a busy evening. AdGuard's
          # own guidance is that this is safe to disable when the server is
          # not reachable from the internet, which is true here: both sites
          # are CGNAT with no forward to port 53.
          ratelimit = 0;
        };

        filtering = {
          protection_enabled = true;
          filtering_enabled = true;
          rewrites_enabled = true;

          # Split-horizon. Rewrites are evaluated before upstream selection
          # and, per AdGuard's docs, are unaffected by `protection_enabled` —
          # so turning blocking off to debug something does not also collapse
          # internal name resolution.
          # ⚠️ `enabled = true` on every entry is not optional and not a
          # default. AdGuard's rewrite schema gained an `enabled` field, and
          # an entry that omits it is migrated to `enabled: false` — so the
          # rules land in AdGuardHome.yaml, look exactly right, and do
          # nothing. Caught on 2026-08-06 only because the resolver was
          # verified before anything was pointed at it: every name still
          # resolved publicly while the config appeared correct.
          rewrites = lib.optionals (cfg.splitHorizonDomain != null) (
            [
              {
                domain = "*.${cfg.splitHorizonDomain}";
                answer = site.ingressVIP;
                enabled = true;
              }
              # ⚠️ The apex needs its own entry — `*.x` does not match `x`.
              # Without it the dashboard at `mvissing.de` resolved publicly at
              # both sites and answered 404 behind an untrusted certificate,
              # while every subdomain worked. See splitHorizonDomain's
              # description for why the Phase 4 exclusion was wrong and what
              # to re-check before putting mail or a public site here.
              {
                domain = cfg.splitHorizonDomain;
                answer = site.ingressVIP;
                enabled = true;
              }
            ]
            # Pass-through exceptions. Two entries per name because the
            # special answer `A` preserves only A records and `AAAA` only
            # AAAA; one without the other silently blackholes the other
            # family.
            ++ lib.concatMap (name: [
              {
                domain = name;
                answer = "A";
                enabled = true;
              }
              {
                domain = name;
                answer = "AAAA";
                enabled = true;
              }
            ])
            cfg.passthroughNames
          );
        };

        # Shared with the roaming resolver on ionos (D15) so the three
        # instances cannot drift into blocking different things. See the file
        # for why that drift would be silent.
        filters = import (lib.custom.relativeToRoot "modules/data/adguard-filters.nix");
      };
    };

    # AdGuard binds a specific address, so it must not start before that
    # address exists. The upstream unit orders itself after network.target
    # only, which is satisfied well before an interface is configured; the
    # Restart=always loop would eventually recover, but noisily and with the
    # site's DNS down for the duration.
    systemd.services.adguardhome = {
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };

    networking.firewall = {
      # 53 on both protocols: TCP is not optional, it is where any answer
      # larger than the UDP limit goes.
      allowedUDPPorts = [53];
      allowedTCPPorts = [53 cfg.uiPort];
    };

    # A DNS server with no way to interrogate DNS is a bad joke — and neither
    # host had `dig` when this phase started, which made every verification
    # step a detour.
    environment.systemPackages = [pkgs.dnsutils];
  };
}
