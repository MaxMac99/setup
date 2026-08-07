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

          # ⚠️ **No rewrites, and that is the design rather than an omission.**
          #
          # The two site resolvers rewrite `*.mvissing.de` to their *own* site's
          # ingress VIP — brink to 192.168.1.240, winkel to 192.168.178.240 —
          # which is why neither of them could serve the tailnet: tailnet DNS is
          # global, so whichever was chosen would hand every client at the other
          # site the wrong VIP.
          #
          # A client at neither site *should* resolve `paperless.mvissing.de` to
          # the public ingress, which is exactly what public DNS already returns.
          # So the correct roaming view is "blocking, no rewrites", and the right
          # implementation of it is an empty list.
          #
          # ⚠️ Consequence worth knowing before debugging: a roaming client
          # reaches apps through ionos's public edge, which is **default-closed**
          # — every app name currently answers 404 behind `TRAEFIK DEFAULT CERT`.
          # Off-LAN access to apps therefore still comes from being *on* the
          # overlay and using the site VIPs, not from this resolver. This makes
          # ad-blocking work while roaming; it does not publish anything.
          rewrites_enabled = true;
          rewrites = [];
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
