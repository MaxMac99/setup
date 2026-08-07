# Public ingress front end on ionos — Phase 9 / D16, Stage A.
#
# Public DNS wildcards *.mvissing.de onto this host (9.1a), so every hostname
# in the estate arrives here. Until now Headscale answered all of them: it held
# both :80 and :443 and serves only its own API, so ingress was not
# "unconfigured" but *shadowed* — names resolved and TLS completed against the
# wrong service. That is why every ACME HTTP-01 challenge returned 403 and no
# certificate could issue for any name.
#
# This module takes :80 only, and splits it by `Host`:
#
#   headscale.mvissing.de  → Headscale's own ACME listener on loopback
#   everything else        → the public Traefik, which serves cert-manager's
#                            HTTP-01 solver Ingresses
#
# ⚠️ **:443 is deliberately not touched.** D16 specifies a `stream` +
# `ssl_preread` SNI split there too, which is what public *service* access
# needs. Certificates do not need it: HTTP-01 validates over port 80, and the
# resulting Secret is served by each site's internal Traefik on the LAN. Since
# Headscale is the overlay control plane — and Brink has no independent way in
# if it breaks (D16) — it keeps its own 443 socket until Stage B is done
# deliberately rather than as a side effect of wanting certificates.
#
# Port 80 cannot be split by SNI: plaintext HTTP has none. Hence an `http`
# block matching on `Host`, which is also why Stage B needs a separate `stream`
# block rather than an extension of this one.
{
  config,
  ...
}: let
  overlay = config.networkConfig.overlay;

  # Where Headscale's ACME listener moved to, so this nginx can own :80.
  # Must match `tls_letsencrypt_listen` in ./overlay-server.nix.
  headscaleAcme = "http://127.0.0.1:8081";

  # The public Traefik's `web` entrypoint.
  #
  # 8000 is the Traefik chart's *container* port for `web` — its `exposedPort:
  # 80` is the Service port, and this Traefik has no Service at all. The pod
  # runs hostNetwork pinned to ionos, so the container port is a host port and
  # loopback reaches it.
  traefikWeb = "http://127.0.0.1:8000";

  # ⚠️ Explicit, because the NixOS module otherwise adds a :443 listener to
  # any vhost and that would collide with Headscale on startup.
  onPort80 = [
    {
      addr = "0.0.0.0";
      port = 80;
      ssl = false;
    }
    {
      addr = "[::]";
      port = 80;
      ssl = false;
    }
  ];
in {
  services.nginx = {
    enable = true;

    # Sets X-Forwarded-For / -Proto / -Host on proxied requests. Traefik is
    # told to trust them from loopback only — see infrastructure/traefik-public.ts.
    recommendedProxySettings = true;

    virtualHosts = {
      # Headscale renews its own certificate and terminates its own TLS. This
      # forwards only the challenge; the control API itself is still reached
      # directly on :443 and does not pass through nginx.
      "${overlay.controlServerHost}" = {
        listen = onPort80;
        locations."/".proxyPass = headscaleAcme;
      };

      # Everything else. Chiefly cert-manager's HTTP-01 solver Ingresses, which
      # exist for a few seconds per challenge.
      #
      # ⚠️ A 404 here is the expected steady state — no challenge is in flight
      # most of the time, and the public Traefik has no routes of its own until
      # Stage B. A 502 means the Traefik pod is not running; that is the
      # failure worth alerting on, not the 404.
      "public-ingress" = {
        default = true;
        listen = onPort80;
        locations."/".proxyPass = traefikWeb;
      };
    };
  };

  # No firewall change: 80 and 443 are already open (./default.nix). The ports
  # behind this — 8000 and 8081 — are not, which is what keeps them private.
  # The IONOS Cloud firewall is default-deny in front of that as a second layer.
}
