# Roaming DNS resolver — the third AdGuard, on ionos. D15, step 1.
#
# ./site-dns.nix serves the two sites. This serves everything that is on the
# overlay and at *neither* site: the phone away from home, the Mac on someone
# else's WiFi. Before it existed such a client had **no ad-blocking and no
# split-horizon at all** — measured from ionos, not assumed: `192.168.1.2:53`
# is unreachable (clients run `--accept-routes=false` per 3.6.1, so they never
# install the subnet route) and `100.64.0.2:53` is unreachable too, because the
# site resolvers deliberately do not bind their overlay address. ionos fell
# through to its provider's DNS at 212.227.123.16.
#
# ⚠️ **This is a separate module rather than a flag on ./site-dns.nix, and the
# reason is the firewall.** That module opens 53 **globally** —
# `networking.firewall.allowedUDPPorts`, every interface — which is right on a
# CGNAT'd host at home and would publish an **open resolver on a public VPS**
# here. Open resolvers are DNS-amplification reflectors and get the host
# nullrouted by its provider. Making it a shared module with a mode flag puts
# that outcome one wrong default away; making it a separate file means the
# global open never exists in this code path at all. The two modules share the
# blocklists (modules/data/adguard-filters.nix) and nothing else.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.roamingDns;
  net = config.networkConfig;
  self = net.hosts.${config.hostSpec.hostName} or null;

  # See ./site-dns.nix for why this answers even though every client passes
  # --accept-dns=false.
  magicDnsResolver = "100.100.100.100";
in {
  options.roamingDns = {
    enable = lib.mkEnableOption "AdGuard Home as the overlay's roaming resolver";

    uiPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = ''
        Port for the admin web interface, bound to **loopback only**.

        ⚠️ Not the overlay address, for two independent reasons. AdGuard starts
        long before `tailscale0` has an address, so binding it would crash-loop
        until it did — the same reason ./site-dns.nix does not bind the overlay
        for DNS either. And the UI has no authentication until a password is
        set by hand in it (`users` is deliberately undeclared so the password
        survives rebuilds), which is a bad thing to expose anywhere and an
        indefensible thing to expose from a public VPS.

        Reach it by forwarding the port over the SSH you already have:
        `ssh -L ${toString 3000}:127.0.0.1:${toString 3000} max@ionos`, then
        http://127.0.0.1:3000.
      '';
    };

    splitHorizonDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "mvissing.de";
      description = ''
        Domain whose names are rewritten to `splitHorizonTarget`. Inert unless
        that option is also set, so this alone changes nothing.
      '';
    };

    splitHorizonTarget = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "192.168.1.240";
      description = ''
        Ingress VIP that `*.<splitHorizonDomain>` and the apex resolve to for
        roaming clients. **Null means no rewrites at all**, which is what D15
        originally specified and remains this module's default.

        ⚠️ **Setting this reverses D15, and the reason the reversal is correct
        is worth recording, because the original reasoning still reads as
        sound.** D15 argued: *"a client at neither site should resolve
        `paperless.mvissing.de` to the public ingress, which is exactly what
        public DNS already returns"* — so the roaming view is "blocking, no
        rewrites", implemented as an empty list.

        That premise was **conditional on Phase 9 publishing something, and
        Phase 9 closed with nothing published.** `traefik-public` is
        default-closed: an Ingress must name `ingressClassName: traefik-public`
        or an IngressRoute carry `ingress=public`, and as of 2026-08-09 nothing
        in `homelab-k8s` does either. So the public address the roaming resolver
        hands out completes TLS against `CN=TRAEFIK DEFAULT CERT` and returns
        **404 for every name**. The decision was not wrong when written; its
        precondition failed and nothing re-examined it. D15 even records the
        consequence — *"off-LAN access to apps therefore still comes from being
        on the overlay and using the site VIPs"* — without noticing that no
        client can reach a site VIP either, because they all run
        `--accept-routes=false`. Two faults, each individually invisible.

        ⚠️ **This only works for clients that accept subnet routes.** The target
        is a LAN address behind a subnet router (`192.168.1.240` is announced by
        MetalLB at Brink), so a client with `--accept-routes=false` resolves the
        name correctly and then cannot reach it — a *worse* failure than today's
        404, because it looks like the service is down. See
        `modules/system/overlay-client.nix` for why every NixOS host keeps
        `--accept-routes=false`, and why roaming clients are the exception.

        ⚠️ **Pick the target site deliberately.** Both site Traefiks serve every
        Ingress in the cluster, so either VIP works — but the one named here is
        the site whose Traefik terminates TLS for roaming clients, and the far
        site's apps are then reached across the WAN overlay twice. Brink holds
        Authentik and Home Assistant, so Brink keeps the login path local.
      '';
    };

    passthroughNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # ⚠️ **Load-bearing, and more so here than in ./site-dns.nix.** There,
        # swallowing the control server costs a site its overlay. Here it is
        # circular: a roaming client would resolve Headscale to a LAN VIP that
        # is only reachable *over the overlay it is trying to establish*, so the
        # client can never recover on its own.
        net.overlay.controlServerHost

        # MagicDNS. Rewrites are applied before upstream selection, so without
        # these the wildcard swallows node names that the
        # `[/mesh.mvissing.de/]100.100.100.100` upstream would answer correctly.
        net.overlay.magicDnsBaseDomain
        "*.${net.overlay.magicDnsBaseDomain}"
      ];
      description = ''
        Names under `splitHorizonDomain` that must keep resolving normally.

        Same mechanism as `./site-dns.nix`: an `answer` of `A`/`AAAA` means
        "keep the upstream's records of that type", and a more specific rewrite
        beats a less specific one, so these win over the wildcard.

        ⚠️ **Check the public zone's shape before adding a name here.** That zone
        is `*.mvissing.de CNAME mvissing.de`, so a pass-through name normally
        returns the apex's public A record in its chain — which every downstream
        cache then files under `mvissing.de`, destroying the apex rewrite for
        everyone. Phase 9 hit exactly this and fixed it by giving
        `headscale.mvissing.de` **explicit A/AAAA records** in the IONOS panel
        (re-verified 2026-08-09: `A 212.132.82.102`, `AAAA 2a02:2479:5c:a00::1`,
        no CNAME). The `mesh.*` names are safe for a different reason — they are
        answered by MagicDNS, which never mentions the apex.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = self != null && self.site == "public";
        message = "roamingDns: ${config.hostSpec.hostName} is not the public-site host. This resolver answers clients that are at no site, and belongs on the one host that is reachable from everywhere; a site host should use siteDns instead.";
      }
      {
        assertion = self == null || self.overlayIPv4 != null;
        message = "roamingDns: ${config.hostSpec.hostName} has no overlayIPv4, so there is no address for Headscale to push to clients.";
      }
      {
        # The same anti-drift check ./site-dns.nix makes between
        # sites.<site>.adguard and the host's lanIPv4, for the same reason. The
        # address is *published* by Headscale in
        # hosts/nixos/ionos/overlay-server.nix and *served* here, and neither
        # file mentions the other. If they drift, every roaming client is
        # pointed at an address nothing listens on, and — because
        # override_local_dns replaces the local resolver rather than
        # supplementing it — the symptom is total DNS failure the moment the
        # VPN connects, which reads as a broken tailnet.
        assertion = self == null || net.overlay.roamingResolver == self.overlayIPv4;
        message = "roamingDns: networkConfig.overlay.roamingResolver is ${toString net.overlay.roamingResolver} but ${config.hostSpec.hostName} serves on ${toString self.overlayIPv4}. Headscale pushes the former to every client and AdGuard answers on the latter — they must not drift.";
      }
    ];

    services.adguardhome = {
      enable = true;

      # Loopback. See uiPort. `openFirewall` is deliberately not used — it
      # would open the UI port on every interface including the public `ens6`.
      host = "127.0.0.1";
      port = cfg.uiPort;

      # Same split as the site resolvers: policy in git, credentials on the
      # host. See ./site-dns.nix for the merge semantics — declared lists are
      # authoritative and replaced wholesale, undeclared keys persist.
      mutableSettings = true;

      settings = {
        dns = {
          # ⚠️ **A wildcard bind, and it is safe here and only here.**
          #
          # ./site-dns.nix binds explicit addresses because brink-server runs
          # systemd-resolved, whose stub holds 127.0.0.53:53. ionos has no such
          # collision — verified on the box 2026-08-07: `systemd-resolved` is
          # **inactive**, and `ss -lntup` shows **nothing at all** listening on
          # 53. Wildcard also removes any ordering dependency on `tailscale0`,
          # which gets its address about 6 s after network-online.target, so
          # this service can start whenever it likes.
          #
          # ⚠️ **What keeps this from being an open resolver is the firewall
          # below, not this line.** The socket really is on the public
          # interface. Two independent things stop the internet reaching it:
          # the host firewall, which admits 53 on `tailscale0` only, and the
          # IONOS Cloud firewall, which is default-deny and permits 22/80/443
          # plus UDP 3478. Neither is visible from the other. Test from off-net
          # after any firewall change: `dig @212.132.82.102 example.com` must
          # time out.
          #
          # IPv4 only. Clients are pushed the v4 address (D15), so a v6
          # listener would add public attack surface serving nobody.
          bind_hosts = ["0.0.0.0"];
          port = 53;

          # Same upstreams as the sites. Bootstraps are literal addresses, so
          # resolving the DoH hostname never needs DNS.
          upstream_dns = [
            "https://1.1.1.1/dns-query"
            "https://1.0.0.1/dns-query"

            # Node names, from tailscaled on this host. A roaming client gets
            # `maxdata.mesh.mvissing.de` for free, without the overlay
            # addresses being written down anywhere.
            #
            # ⚠️ Not a general upstream, and must not become one: 100.100.100.100
            # is tailscaled, which for names outside base_domain forwards to
            # whatever DNS the tailnet was pushed — i.e. back to this AdGuard.
            # Scoped to the one suffix, that loop cannot form.
            "[/${net.overlay.magicDnsBaseDomain}/]${magicDnsResolver}"
          ];
          bootstrap_dns = ["1.1.1.1" "1.0.0.1"];
          upstream_mode = "load_balance";

          # ⚠️ No router to ask, so do not let AdGuard guess one. Left on, it
          # infers "local" PTR resolvers from the host's own resolv.conf, which
          # on ionos is the provider's servers — private-range PTR queries
          # would leak to them.
          use_private_ptr_resolvers = false;
          local_ptr_upstreams = [];

          # ⚠️ **Kept on, unlike the site resolvers — do not copy `ratelimit =
          # 0` from ./site-dns.nix.** That zero is justified there by the hosts
          # being unreachable from the internet under CGNAT with no forward to
          # 53. This socket is bound on a public VPS, so the justification does
          # not carry, and an unrated open resolver is precisely the thing that
          # gets a VPS nullrouted if either firewall is ever wrong. This is the
          # third layer, and the only one inside this file.
          #
          # The site module's actual complaint was never the limit, it was the
          # bucket: `ratelimit_subnet_len_ipv4` defaults to **24**, so a whole
          # /24 shares one allowance. The overlay is a /24-shaped space too, so
          # the default would put every roaming client in one bucket. `32`
          # gives each client its own, and 100 qps is far above what a browser
          # bursts to while still bounding reflection hard.
          #
          # ⚠️ Confirm both keys survived into the rendered AdGuardHome.yaml
          # after the first start. An unknown key is dropped by the module's
          # yaml-merge without complaint — the same silent-acceptance failure
          # as the `enabled` field on rewrites (Phase 4).
          ratelimit = 100;
          ratelimit_subnet_len_ipv4 = 32;
        };

        filtering = {
          protection_enabled = true;
          filtering_enabled = true;

          # Split-horizon for roaming clients — **off unless
          # `splitHorizonTarget` is set**, which keeps D15's original "blocking,
          # no rewrites" as this module's default. See that option for why the
          # reversal is correct and what it costs.
          #
          # The shape differs from ./site-dns.nix in one way worth noting: that
          # module derives the answer from `site.ingressVIP`, i.e. *this* site's
          # Traefik. A roaming client is at no site, so there is nothing to
          # derive from and the target has to be named explicitly by the host.
          #
          # ⚠️ `enabled = true` on every entry is not a default and not
          # optional. AdGuard's rewrite schema has an `enabled` field, and an
          # entry omitting it is migrated to `enabled: false` — the rules land
          # in AdGuardHome.yaml, read exactly right, and do nothing. Phase 4
          # caught this only because the resolver was verified before anything
          # was pointed at it.
          rewrites_enabled = true;
          rewrites = lib.optionals (cfg.splitHorizonDomain != null && cfg.splitHorizonTarget != null) (
            [
              {
                domain = "*.${cfg.splitHorizonDomain}";
                answer = cfg.splitHorizonTarget;
                enabled = true;
              }
              # ⚠️ The apex needs its own entry — `*.x` does not match `x`.
              # Homepage lives at the bare `mvissing.de`, and Phase 9 spent a
              # session on precisely this omission at the site resolvers.
              {
                domain = cfg.splitHorizonDomain;
                answer = cfg.splitHorizonTarget;
                enabled = true;
              }
            ]
            # Two entries per pass-through name: the special answer `A`
            # preserves only A records and `AAAA` only AAAA, so one without the
            # other silently blackholes the opposite family.
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

        # Shared with ./site-dns.nix so the three instances cannot drift into
        # blocking different things.
        filters = import (lib.custom.relativeToRoot "modules/data/adguard-filters.nix");
      };
    };

    # Ordered after the network for the same reason as the site resolvers, even
    # though the wildcard bind means it could start earlier: the upstreams are
    # DoH, so a start before routing exists just means a burst of failed
    # lookups and a confusing first minute in the query log.
    systemd.services.adguardhome = {
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };

    # ⚠️ **The load-bearing part of this module.** Scoped to the overlay
    # interface and never to `allowedTCPPorts`/`allowedUDPPorts`, which apply
    # to every interface including the public `ens6`.
    #
    # Same reasoning as the k3s ports in ./k3s-base.nix, which were global here
    # until Phase 7 and left etcd's ports accepted at the host firewall with
    # only the IONOS Cloud panel between them and the internet. Note the
    # per-interface lists are **additive**: an empty `ens6` block subtracts
    # nothing from a global open, so there is no way to walk a mistake back
    # except by not making it.
    #
    # The UI port is deliberately absent — it is bound to loopback and reached
    # over SSH, so it needs no rule on any interface.
    networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
      allowedUDPPorts = [53];
      # TCP is not optional: it is where any answer too large for UDP goes.
      allowedTCPPorts = [53];
    };

    environment.systemPackages = [pkgs.dnsutils];
  };
}
